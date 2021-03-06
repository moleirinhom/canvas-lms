#
# Copyright (C) 2011 Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe PseudonymSessionsController do

  it "should render normal layout if not iphone/ipod" do
    get 'new'
    response.should render_template("pseudonym_sessions/new.html.erb")
  end

  it "should render special iPhone/iPod layout if coming from one of those" do
    [
      "Mozilla/5.0 (iPhone; U; CPU iPhone OS 4_3_3 like Mac OS X; en-us) AppleWebKit/533.17.9 (KHTML, like Gecko) Version/5.0.2 Mobile/8J2 Safari/6533.18.5",
      "Mozilla/5.0 (iPod; U; CPU iPhone OS 4_3_3 like Mac OS X; en-us) AppleWebKit/533.17.9 (KHTML, like Gecko) Version/5.0.2 Mobile/8J2 Safari/6533.18.5"
    ].each do |user_agent|
      request.env['HTTP_USER_AGENT'] = user_agent
      get 'new'
      response.should render_template("pseudonym_sessions/mobile_login")
    end
  end

  it "should render special iPhone/iPod layout if coming from one of those and it's the wrong password'" do
    [
      "Mozilla/5.0 (iPhone; U; CPU iPhone OS 4_3_3 like Mac OS X; en-us) AppleWebKit/533.17.9 (KHTML, like Gecko) Version/5.0.2 Mobile/8J2 Safari/6533.18.5",
      "Mozilla/5.0 (iPod; U; CPU iPhone OS 4_3_3 like Mac OS X; en-us) AppleWebKit/533.17.9 (KHTML, like Gecko) Version/5.0.2 Mobile/8J2 Safari/6533.18.5"
    ].each do |user_agent|
      request.env['HTTP_USER_AGENT'] = user_agent
      post 'create'
      response.should render_template("pseudonym_sessions/mobile_login")
    end
  end

  it "should re-render if no user" do
    post 'create'
    response.status.should == '400 Bad Request'
    response.should render_template('new')
  end

  it "should re-render if incorrect password" do
    user_with_pseudonym(:username => 'jt@instructure.com', :active_all => 1, :password => 'qwerty')
    post 'create', :pseudonym_session => { :unique_id => 'jt@instructure.com', :password => 'dvorak'}
    response.status.should == '400 Bad Request'
    response.should render_template('new')
  end

  it "password auth should work" do
    user_with_pseudonym(:username => 'jt@instructure.com', :active_all => 1, :password => 'qwerty')
    post 'create', :pseudonym_session => { :unique_id => 'jt@instructure.com', :password => 'qwerty'}
    response.should be_redirect
    response.should redirect_to(dashboard_url(:login_success => 1))
    assigns[:user].should == @user
    assigns[:pseudonym].should == @pseudonym
    assigns[:pseudonym_session].should_not be_nil
  end

  context "trusted logins" do
    before do
      Pseudonym.stubs(:trusted_by).with(Account.default).returns(Pseudonym.scoped({}))
    end

    it "should login for a pseudonym from a different account" do
      account = Account.create!
      Account.any_instance.stubs(:trusted_account_ids).returns([account.id])
      user_with_pseudonym(:username => 'jt@instructure.com', :active_all => 1, :password => 'qwerty', :account => account)
      post 'create', :pseudonym_session => { :unique_id => 'jt@instructure.com', :password => 'qwerty'}
      response.should redirect_to(dashboard_url(:login_success => 1))
      flash[:notice].should == "Login successful."
    end

    it "should login for a user with multiple identical pseudonyms" do
      account1 = Account.create!
      user_with_pseudonym(:username => 'jt@instructure.com', :active_all => 1, :password => 'qwerty', :account => account1)
      @pseudonym = @user.pseudonyms.create!(:account => Account.site_admin, :unique_id => 'jt@instructure.com', :password => 'qwerty', :password_confirmation => 'qwerty')
      post 'create', :pseudonym_session => { :unique_id => 'jt@instructure.com', :password => 'qwerty'}
      response.should redirect_to(dashboard_url(:login_success => 1))
      # it should have preferred the site admin pseudonym
      assigns[:pseudonym].should == @pseudonym
      flash[:notice].should == "Login successful."
    end

    it "should not login for multiple users with identical pseudonyms" do
      account1 = Account.create!
      account2 = Account.create!
      Account.any_instance.stubs(:trusted_account_ids).returns([account1.id, account2.id])
      user_with_pseudonym(:username => 'jt@instructure.com', :active_all => 1, :password => 'qwerty', :account => account1)
      user_with_pseudonym(:username => 'jt@instructure.com', :active_all => 1, :password => 'qwerty', :account => account2)
      post 'create', :pseudonym_session => { :unique_id => 'jt@instructure.com', :password => 'qwerty'}
      response.should_not be_success
      response.should render_template('pseudonym_sessions/new')
    end

    it "should warn for deprecated trust method" do
      account = Account.create!
      user_with_pseudonym(:username => 'jt@instructure.com', :active_all => 1, :password => 'qwerty', :account => account)
      HostUrl.stubs(:context_host).with(Account.default).returns('www.example.com')
      HostUrl.expects(:context_host).with(account).returns('somewhere.else.com')
      post 'create', :pseudonym_session => { :unique_id => 'jt@instructure.com', :password => 'qwerty'}
      response.should redirect_to(dashboard_url(:login_success => 1))
      flash[:notice].should be_blank
      flash[:error].should == 'In the future, please login at somewhere.else.com.'
    end
  end

  context "merging" do
    it "should set merge params correctly in the session" do
      user_with_pseudonym(:username => 'jt@instructure.com', :active_all => 1, :password => 'qwerty')
      @cc = @user.communication_channels.create!(:path => 'jt+1@instructure.com')
      get 'new', :confirm => @cc.confirmation_code, :expected_user_id => @user.id
      response.should render_template 'new'
      session[:confirm].should == @cc.confirmation_code
      session[:expected_user_id].should == @user.id
    end

    it "should redirect back to merge users" do
      user_with_pseudonym(:username => 'jt@instructure.com', :active_all => 1, :password => 'qwerty')
      @cc = @user.communication_channels.create!(:path => 'jt+1@instructure.com')
      session[:confirm] = @cc.confirmation_code
      session[:expected_user_id] = @user.id
      post 'create', :pseudonym_session => { :unique_id => 'jt@instructure.com', :password => 'qwerty' }
      response.should redirect_to(registration_confirmation_url(@cc.confirmation_code, :login_success => 1, :enrollment => nil, :confirm => 1))
    end
  end

  context "saml" do
    it "should scope logins to the correct domain root account" do
      Setting.set_config("saml", {})
      unique_id = 'foo@example.com'

      account1 = account_with_saml
      user1 = user_with_pseudonym({:active_all => true, :username => unique_id})
      @pseudonym.account = account1
      @pseudonym.save!

      account2 = account_with_saml
      user2 = user_with_pseudonym({:active_all => true, :username => unique_id})
      @pseudonym.account = account2
      @pseudonym.save!

      controller.stubs(:saml_response).returns(
        stub('response', :is_valid? => true, :success_status? => true, :name_id => unique_id, :name_qualifier => nil, :session_index => nil)
      )

      controller.request.env['canvas.domain_root_account'] = account1
      get 'saml_consume', :SAMLResponse => "foo"
      response.should redirect_to(dashboard_url(:login_success => 1))
      session[:name_id].should == unique_id
      Pseudonym.find(session[:pseudonym_credentials_id]).should == user1.pseudonyms.first

      (controller.instance_variables.grep(/@[^_]/) - ['@mock_proxy']).each{ |var| controller.send :remove_instance_variable, var }
      session.reset

      controller.stubs(:saml_response).returns(
        stub('response', :is_valid? => true, :success_status? => true, :name_id => unique_id, :name_qualifier => nil, :session_index => nil)
      )

      controller.request.env['canvas.domain_root_account'] = account2
      get 'saml_consume', :SAMLResponse => "bar"
      response.should redirect_to(dashboard_url(:login_success => 1))
      session[:name_id].should == unique_id
      Pseudonym.find(session[:pseudonym_credentials_id]).should == user2.pseudonyms.first

      Setting.set_config("saml", nil)
    end

    it "should redirect to RelayState relative urls" do
      Setting.set_config("saml", {})
      unique_id = 'foo@example.com'

      account = account_with_saml
      user = user_with_pseudonym({:active_all => true, :username => unique_id})
      @pseudonym.account = account
      @pseudonym.save!

      controller.stubs(:saml_response).returns(
        stub('response', :is_valid? => true, :success_status? => true, :name_id => unique_id, :name_qualifier => nil, :session_index => nil)
      )

      controller.request.env['canvas.domain_root_account'] = account
      get 'saml_consume', :SAMLResponse => "foo", :RelayState => "/courses"
      response.should redirect_to(courses_url)
      session[:name_id].should == unique_id
    end
  end

  context "cas" do
    def stubby(stub_response, use_mock = true)
      cas_client = use_mock ? stub_everything(:cas_client) : controller.cas_client
      cas_client.instance_variable_set(:@stub_response, stub_response)
      def cas_client.validate_service_ticket(st)
        st.response = CASClient::ValidationResponse.new(@stub_response)
      end
      PseudonymSessionsController.any_instance.stubs(:cas_client).returns(cas_client) if use_mock
    end

    it "should scope logins to the correct domain root account" do
      unique_id = 'foo@example.com'

      account1 = account_with_cas
      user1 = user_with_pseudonym({:active_all => true, :username => unique_id})
      @pseudonym.account = account1
      @pseudonym.save!

      account2 = account_with_cas
      user2 = user_with_pseudonym({:active_all => true, :username => unique_id})
      @pseudonym.account = account2
      @pseudonym.save!

      stubby("yes\n#{unique_id}\n")

      controller.request.env['canvas.domain_root_account'] = account1
      get 'new', :ticket => 'ST-abcd'
      response.should redirect_to(dashboard_url(:login_success => 1))
      session[:cas_login].should == true
      Pseudonym.find(session[:pseudonym_credentials_id]).should == user1.pseudonyms.first

      (controller.instance_variables.grep(/@[^_]/) - ['@mock_proxy']).each{ |var| controller.send :remove_instance_variable, var }
      session.reset

      stubby("yes\n#{unique_id}\n")

      controller.request.env['canvas.domain_root_account'] = account2
      get 'new', :ticket => 'ST-efgh'
      response.should redirect_to(dashboard_url(:login_success => 1))
      session[:cas_login].should == true
      Pseudonym.find(session[:pseudonym_credentials_id]).should == user2.pseudonyms.first
    end
  end
end

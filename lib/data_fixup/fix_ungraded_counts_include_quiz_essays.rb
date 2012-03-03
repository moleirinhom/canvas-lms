module DataFixup::FixUngradedCountsIncludeQuizEssays
  def self.run
    Assignment.connection.execute <<-SQL
      UPDATE assignments SET needs_grading_count = COALESCE((
        SELECT COUNT(DISTINCT s.id)
        FROM submissions s
        INNER JOIN enrollments e ON e.user_id = s.user_id AND e.workflow_state = 'active'
        WHERE s.assignment_id = assignments.id
          AND e.course_id = assignments.context_id
          AND s.submission_type IS NOT NULL
          AND (s.workflow_state = 'pending_review'
            OR (s.workflow_state = 'submitted' 
              AND (s.score IS NULL OR NOT s.grade_matches_current_submission)
            )
          )
      ), 0)
      SQL
  end
end
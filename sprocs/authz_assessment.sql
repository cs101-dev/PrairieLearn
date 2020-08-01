DROP FUNCTION IF EXISTS authz_assessment(bigint,jsonb);
DROP FUNCTION IF EXISTS authz_assessment(bigint,jsonb,text);
DROP FUNCTION IF EXISTS authz_assessment(bigint,jsonb,timestamptz,text);

CREATE OR REPLACE FUNCTION
    authz_assessment (
        IN assessment_id bigint,
        IN authz_data JSONB,
        IN req_date timestamptz,
        IN display_timezone text,
        OUT authorized boolean,      -- Is this assessment available for the given user?
        OUT authorized_edit boolean, -- Is this assessment available for editing by the given user?
        OUT credit integer,          -- How much credit will they receive?
        OUT credit_date_string TEXT, -- For display to the user.
        OUT time_limit_min integer,  -- The time limit (if any) for this assessment.
        OUT password text,           -- The password (if any) for this assessment.
        OUT mode enum_mode,          -- The mode for this assessment.
        OUT seb_config JSONB,        -- The SEB config (if any) for this assessment.
        OUT show_closed_assessment boolean, -- If students can view the assessment after it is closed.
        OUT access_rules JSONB       -- For display to the user. The currently active rule is marked by 'active' = TRUE.
    )
AS $$
DECLARE
    user_result record;
BEGIN
    -- authorization for the effective user
    SELECT *
    INTO user_result
    FROM
        check_assessment_access(
            assessment_id,
            (authz_data->>'mode')::enum_mode,
            (authz_data->>'course_role')::enum_course_role,
            (authz_data->>'course_instance_role')::enum_course_instance_role,
            (authz_data->'user'->>'user_id')::bigint,
            authz_data->'user'->>'uid',
            req_date,
            display_timezone
        );

    -- Assessment access is granted based only on effective user permissions.
    --
    -- You might wonder if it is necessary to check authn user permissions as well.
    -- There are two things in particular you might worry about:
    --
    -- 1) Does the effective user have more permissions than the authn user?
    --
    --      No. We have already verified (middlewares/authzCourseOrInstance) that
    --      the effective user has no more permissions than the authn user, throwing
    --      an error otherwise.
    --
    -- 2) Is the effective user a student, and if so does the authn user have
    --    permission to view or edit student data?
    --
    --      This concern only makes sense if the effective user has a different UID
    --      than the authn user. There are two possibilities:
    --
    --      a) The effective user is an instructor. In this case, there is no need
    --         to worry about student data permissions.
    --
    --      b) The effective user is a student. In this case, we would want to restrict
    --         access depending on the course instance role of the authn user. However,
    --         an authn user must be a "Student Data Editor" in order to emulate an
    --         effective user with a different UID who is a student - again, this has
    --         already been verified (middlewares/authzCourseOrInstance). So, we already
    --         know that the authn user has exactly the course instance role that would
    --         be required to keep access.
    --
    --       When we say that the effective user "is a student" or "is an instructor"
    --       in this context, we mean without other overrides.
    --
    --  In short, don't worry about authn permissions.
    --
    --  Note that the situation is different for assessment instance access, because
    --  an assessment instance - unlike an assessment - is associated with a particular
    --  user (see authz_assessment_instance).
    --
    --  You might also wonder why we bother to distinguish between view (authorized)
    --  and edit (authorized_edit) permissions, when clearly they will always be the
    --  same. This is for legacy reasons and is something that should be cleaned up.
    authorized := user_result.authorized;
    authorized_edit := user_result.authorized;

    -- all other variables are from the effective user authorization
    credit := user_result.credit;
    credit_date_string := user_result.credit_date_string;
    time_limit_min := user_result.time_limit_min;
    password := user_result.password;
    access_rules := user_result.access_rules;
    mode := user_result.mode;
    seb_config := user_result.seb_config;
    show_closed_assessment := user_result.show_closed_assessment;
END;
$$ LANGUAGE plpgsql VOLATILE;

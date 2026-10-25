--
--  prd_v03_regression.sql
--  OurLeague
--
--  Created by 양호준 on 2026/10/19.
--

BEGIN;

DO $$
#variable_conflict use_variable
DECLARE
    owner_id uuid := gen_random_uuid();
    other_id uuid := gen_random_uuid();
    club_a uuid;
    club_b uuid;
    club_c uuid;
    session_id uuid;
    guest_session_id uuid;
    participant_ids uuid[] := ARRAY[]::uuid[];
    attendance_ids uuid[];
    court_ids uuid[];
    match_ids uuid[];
    command_id uuid := gen_random_uuid();
    result_id uuid;
    membership_id uuid;
    guest_id uuid;
    guest_extra_id uuid;
    club_result jsonb;
    output jsonb;
    preview jsonb;
    invitation jsonb;
    replacement jsonb;
    bad_schedule jsonb;
    browser_token text := encode(extensions.gen_random_bytes(32),'hex');
    extra_token text := encode(extensions.gen_random_bytes(32),'hex');
    payload jsonb;
    player_number integer;
    rejected boolean;
BEGIN
    INSERT INTO auth.users(id) VALUES (owner_id),(other_id);
    PERFORM set_config('request.jwt.claim.sub',owner_id::text,true);
    SET LOCAL ROLE authenticated;
    club_result := public.league_command('create_club','{"name":"Regression A"}'::jsonb,command_id);
    club_a := (club_result->>'id')::uuid;
    ASSERT club_result=public.league_command('create_club','{"name":"Regression A"}'::jsonb,command_id),'create retry changed result';
    rejected := false;
    BEGIN
        PERFORM public.league_command('create_club','{"name":"Changed"}'::jsonb,command_id);
    EXCEPTION WHEN unique_violation THEN rejected := true; END;
    ASSERT rejected,'request ID reuse was accepted';

    PERFORM set_config('request.jwt.claim.sub',other_id::text,true);
    output := public.league_command('create_club','{"name":"Regression B"}'::jsonb,gen_random_uuid());
    club_b := (output->>'id')::uuid;
    output := public.league_command('create_club','{"name":"Regression C"}'::jsonb,gen_random_uuid());
    club_c := (output->>'id')::uuid;
    invitation := public.issue_invitation(club_b,NULL,now()+interval '1 day');
    PERFORM set_config('request.jwt.claim.sub',owner_id::text,true);
    output := public.league_command('request_membership',jsonb_build_object('token',invitation->>'token'),gen_random_uuid());
    membership_id := (output->>'membership_id')::uuid;
    ASSERT NOT EXISTS(SELECT 1 FROM public.clubs WHERE id=club_b),'pending member could read club';
    PERFORM set_config('request.jwt.claim.sub',other_id::text,true);
    PERFORM public.league_command('approve_membership',jsonb_build_object('club_id',club_b,'membership_id',membership_id),gen_random_uuid());
    PERFORM set_config('request.jwt.claim.sub',owner_id::text,true);
    ASSERT (SELECT count(*) FROM public.clubs WHERE id IN (club_a,club_b,club_c))=2,'multiple club membership isolation failed';
    rejected := false;
    BEGIN
        PERFORM public.league_command('save_participant',jsonb_build_object('club_id',club_b,'display_name','Unauthorized'),gen_random_uuid());
    EXCEPTION WHEN insufficient_privilege THEN rejected := true; END;
    ASSERT rejected,'club A owner acquired club B owner privilege';
    rejected := false;
    BEGIN
        INSERT INTO public.clubs(name,owner_account_id) VALUES ('Direct write',owner_id);
    EXCEPTION WHEN insufficient_privilege THEN rejected := true; END;
    ASSERT rejected,'direct table write was allowed';

    FOR player_number IN 1..8 LOOP
        output := public.league_command('save_participant',jsonb_build_object('club_id',club_a,'display_name','Player '||player_number,
            'account_id',CASE WHEN player_number=1 THEN owner_id ELSE NULL END),gen_random_uuid());
        participant_ids := array_append(participant_ids,(output->>'participant_id')::uuid);
    END LOOP;
    output := public.league_command('create_session',jsonb_build_object('club_id',club_a,'title','Parallel doubles',
        'starts_at',now()+interval '1 day','ends_at',now()+interval '26 hours','attendance_deadline',now()+interval '12 hours',
        'location','Test court','capacity',8,'court_count',2,'round_count',2),gen_random_uuid());
    session_id := (output->>'id')::uuid;
    FOR player_number IN 1..8 LOOP
        PERFORM public.league_command('respond_attendance',jsonb_build_object('session_id',session_id,
            'club_participant_id',participant_ids[player_number],'response','attending'),gen_random_uuid());
    END LOOP;
    preview := public.league_command('preview_schedule',jsonb_build_object('session_id',session_id,'seed',42),gen_random_uuid());
    ASSERT jsonb_array_length(preview->'matches')=4,'8 people / 2 courts / 2 rounds should produce 4 matches';
    ASSERT (SELECT bool_and(value::int=2) FROM jsonb_each_text(preview->'appearances')),'unequal generated appearances';
    output := public.league_command('preview_schedule',jsonb_build_object('session_id',session_id,'seed',42),gen_random_uuid());
    ASSERT output=preview,'seed is not reproducible';
    payload := jsonb_build_object('session_id',session_id,'matches',preview->'matches','seed',42,
        'expected_roster_version',(preview->>'roster_version')::int,'expected_schedule_version',0);
    SELECT array_agg(id ORDER BY array_position(participant_ids,club_participant_id)) INTO attendance_ids
        FROM public.session_participants WHERE session_participants.session_id=session_id;
    SELECT array_agg(id ORDER BY position) INTO court_ids FROM public.session_courts WHERE session_courts.session_id=session_id;
    payload := payload||jsonb_build_object('matches',jsonb_build_array(
        jsonb_build_object('round_index',1,'court_id',court_ids[1],'team_a',attendance_ids[1:2],'team_b',attendance_ids[3:4]),
        jsonb_build_object('round_index',1,'court_id',court_ids[2],'team_a',attendance_ids[5:6],'team_b',attendance_ids[7:8]),
        jsonb_build_object('round_index',2,'court_id',court_ids[1],'team_a',ARRAY[attendance_ids[1],attendance_ids[5]],'team_b',ARRAY[attendance_ids[2],attendance_ids[6]]),
        jsonb_build_object('round_index',2,'court_id',court_ids[2],'team_a',ARRAY[attendance_ids[3],attendance_ids[7]],'team_b',ARRAY[attendance_ids[4],attendance_ids[8]])
    ));
    rejected := false;
    BEGIN
        PERFORM public.league_command('confirm_schedule',payload||'{"expected_roster_version":-1}'::jsonb,gen_random_uuid());
    EXCEPTION WHEN serialization_failure THEN rejected := true; END;
    ASSERT rejected,'stale roster was accepted';
    bad_schedule := jsonb_set(preview->'matches','{0,team_b,0}',preview->'matches'->0->'team_a'->0);
    rejected := false;
    BEGIN
        PERFORM public.league_command('confirm_schedule',payload||jsonb_build_object('matches',bad_schedule),gen_random_uuid());
    EXCEPTION WHEN unique_violation THEN rejected := true; END;
    ASSERT rejected,'duplicate player was accepted';
    PERFORM public.league_command('confirm_schedule',payload,gen_random_uuid());
    SET LOCAL ROLE postgres;
    rejected := false;
    BEGIN
        INSERT INTO public.matches(session_id,round_index,court_id,schedule_version)
            VALUES (session_id,3,court_ids[1],1) RETURNING id INTO result_id;
        FOR player_number IN 1..3 LOOP
            INSERT INTO public.match_players(match_id,session_id,participant_id,team,slot)
                VALUES (result_id,session_id,attendance_ids[player_number],CASE WHEN player_number<3 THEN 'a' ELSE 'b' END,
                    CASE WHEN player_number=2 THEN 2 ELSE 1 END);
        END LOOP;
        SET CONSTRAINTS ALL IMMEDIATE;
    EXCEPTION WHEN check_violation THEN
        ASSERT SQLERRM='match_requires_four_players','unexpected deferred validation failure';
        rejected := true;
    END;
    ASSERT rejected,'three-player match was accepted';
    SET CONSTRAINTS ALL DEFERRED;
    SET LOCAL ROLE authenticated;
    SELECT array_agg(id ORDER BY round_index,court_id) INTO match_ids FROM public.matches WHERE matches.session_id=session_id AND status='pending';
    PERFORM public.league_command('start_match',jsonb_build_object('match_id',match_ids[1],'expected_schedule_version',1),gen_random_uuid());
    PERFORM public.league_command('start_match',jsonb_build_object('match_id',match_ids[2],'expected_schedule_version',1),gen_random_uuid());
    ASSERT (SELECT count(*) FROM public.matches WHERE matches.session_id=session_id AND status='in_progress')=2,'independent court start failed';
    SET LOCAL ROLE postgres;
    rejected := false;
    BEGIN UPDATE public.match_players SET team='b' WHERE match_id=match_ids[1] AND team='a';
    EXCEPTION WHEN check_violation THEN rejected := true; END;
    ASSERT rejected,'started match team was editable';
    SET LOCAL ROLE authenticated;
    rejected := false;
    BEGIN
        PERFORM public.league_command('start_match',jsonb_build_object('match_id',match_ids[3],'expected_schedule_version',1),gen_random_uuid());
    EXCEPTION WHEN raise_exception THEN rejected := true; END;
    ASSERT rejected,'busy court accepted another match';
    rejected := false;
    BEGIN
        PERFORM public.league_command('save_result',jsonb_build_object('match_id',match_ids[1],'winner','a',
            'expected_result_version',0,'score_a',3,'score_b',3),gen_random_uuid());
    EXCEPTION WHEN check_violation THEN rejected := true; END;
    ASSERT rejected,'tied winner score was accepted';
    command_id := gen_random_uuid();
    payload := jsonb_build_object('match_id',match_ids[1],'winner','a','expected_result_version',0);
    output := public.league_command('save_result',payload,command_id);
    ASSERT output=public.league_command('save_result',payload,command_id),'result retry changed result';
    ASSERT (SELECT count(*) FROM public.result_revisions WHERE match_id=match_ids[1])=1,'duplicate result audit record';
    ASSERT (SELECT sum(wins) FROM public.participant_stats WHERE club_id=club_a)=2,'initial wins should total two';
    ASSERT (SELECT sum(losses) FROM public.participant_stats WHERE club_id=club_a)=2,'initial losses should total two';
    ASSERT (SELECT sum(completed_matches) FROM public.participant_stats WHERE club_id=club_a)=4,'pending matches counted in statistics';
    rejected := false;
    BEGIN
        PERFORM public.league_command('start_match',jsonb_build_object('match_id',match_ids[3],'expected_schedule_version',1),gen_random_uuid());
    EXCEPTION WHEN raise_exception THEN
        ASSERT SQLERRM='participant_already_playing','wrong cross-court blocking reason';
        rejected := true;
    END;
    ASSERT rejected,'same participant started on a different free court';
    rejected := false;
    BEGIN
        PERFORM public.league_command('save_result',jsonb_build_object('match_id',match_ids[1],'winner','b',
            'expected_result_version',0,'reason','Correction'),gen_random_uuid());
    EXCEPTION WHEN serialization_failure THEN rejected := true; END;
    ASSERT rejected,'stale result was accepted';
    PERFORM public.league_command('save_result',jsonb_build_object('match_id',match_ids[1],'winner','b',
        'expected_result_version',1,'reason','Correction'),gen_random_uuid());
    ASSERT (SELECT count(*) FROM public.result_revisions WHERE match_id=match_ids[1])=2,'correction history missing';
    ASSERT (SELECT sum(completed_matches) FROM public.participant_stats WHERE club_id=club_a)=4,'correction double-counted appearances';
    PERFORM public.league_command('abort_match',jsonb_build_object('match_id',match_ids[2]),gen_random_uuid());
    ASSERT (SELECT sum(appearances) FROM public.participant_stats WHERE club_id=club_a)=8,'aborted match not counted as appearance';
    ASSERT (SELECT sum(completed_matches) FROM public.participant_stats WHERE club_id=club_a)=4,'aborted match counted as win/loss';
    PERFORM public.league_command('cancel_match',jsonb_build_object('match_id',match_ids[3]),gen_random_uuid());
    PERFORM public.league_command('cancel_match',jsonb_build_object('match_id',match_ids[4]),gen_random_uuid());
    PERFORM public.league_command('complete_session',jsonb_build_object('session_id',session_id),gen_random_uuid());
    PERFORM public.league_command('invalidate_result',jsonb_build_object('match_id',match_ids[1],
        'expected_result_version',2,'reason','Wrong historical lineup'),gen_random_uuid());
    ASSERT (SELECT sum(completed_matches) FROM public.participant_stats WHERE club_id=club_a)=0,'invalidated result counted in statistics';
    ASSERT (SELECT bool_and(win_rate IS NULL) FROM public.participant_stats WHERE club_id=club_a),'zero-match win rate should be NULL';

    output := public.league_command('create_session',jsonb_build_object('club_id',club_a,'title','Guest capacity',
        'starts_at',now()+interval '1 day','ends_at',now()+interval '26 hours','attendance_deadline',now()+interval '12 hours',
        'location','Test court','capacity',4,'court_count',1,'round_count',1),gen_random_uuid());
    guest_session_id := (output->>'id')::uuid;
    SELECT array_agg(id ORDER BY position) INTO court_ids FROM public.session_courts WHERE session_courts.session_id=guest_session_id;
    PERFORM public.league_command('update_session',jsonb_build_object('session_id',guest_session_id,
        'court_count',2,'expected_roster_version',0),gen_random_uuid());
    PERFORM public.league_command('update_session',jsonb_build_object('session_id',guest_session_id,
        'court_count',1,'expected_roster_version',1),gen_random_uuid());
    ASSERT (SELECT id FROM public.session_courts WHERE session_courts.session_id=guest_session_id AND position=1)=court_ids[1],
        'court identity changed during resize';
    ASSERT (SELECT count(*) FROM public.session_courts WHERE session_courts.session_id=guest_session_id AND is_active)=1,
        'inactive courts counted toward capacity';
    PERFORM public.league_command('rename_court',jsonb_build_object('session_id',guest_session_id,'court_id',court_ids[1],
        'name','Renamed court'),gen_random_uuid());
    ASSERT (SELECT name FROM public.session_courts WHERE id=court_ids[1])='Renamed court','court rename failed';
    FOR player_number IN 1..3 LOOP
        PERFORM public.league_command('respond_attendance',jsonb_build_object('session_id',guest_session_id,
            'club_participant_id',participant_ids[player_number],'response','attending'),gen_random_uuid());
    END LOOP;
    invitation := public.issue_invitation(club_a,guest_session_id,now()+interval '1 day');
    SET LOCAL ROLE anon;
    PERFORM set_config('request.jwt.claim.sub','',true);
    output := public.guest_access('invite',invitation->>'token');
    ASSERT NOT output ? 'participants','invite leaked participant list';
    output := public.guest_access('submit',invitation->>'token',browser_token,'Guest A','attending');
    guest_id := (output->'self'->>'id')::uuid;
    ASSERT NOT output ? 'participants','pending guest leaked participant list';
    output := public.guest_access('submit',invitation->>'token',browser_token,'Guest A','attending');
    ASSERT (output->'self'->>'id')::uuid=guest_id,'browser resubmission created duplicate guest';
    rejected := false;
    BEGIN PERFORM 1 FROM private.guest_sessions;
    EXCEPTION WHEN insufficient_privilege THEN rejected := true; END;
    ASSERT rejected,'raw guest tokens were accessible';
    rejected := false;
    BEGIN PERFORM 1 FROM public.session_participants;
    EXCEPTION WHEN insufficient_privilege THEN rejected := true; END;
    ASSERT rejected,'anon could access participant table';
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub',owner_id::text,true);
    PERFORM public.league_command('approve_guest',jsonb_build_object('session_id',guest_session_id,'participant_id',guest_id,'approval','approved'),gen_random_uuid());
    SET LOCAL ROLE anon;
    PERFORM set_config('request.jwt.claim.sub','',true);
    output := public.guest_access('view',NULL,browser_token);
    ASSERT jsonb_array_length(output->'participants')=4,'approved guest cannot view their session';
    ASSERT NOT (output->'session') ? 'club_id','guest response exposed club scope';
    output := public.guest_access('submit',invitation->>'token',extra_token,'Guest B','attending');
    guest_extra_id := (output->'self'->>'id')::uuid;
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub',owner_id::text,true);
    rejected := false;
    BEGIN
        PERFORM public.league_command('approve_guest',jsonb_build_object('session_id',guest_session_id,
            'participant_id',guest_extra_id,'approval','approved'),gen_random_uuid());
        SET CONSTRAINTS ALL IMMEDIATE;
    EXCEPTION WHEN check_violation THEN rejected := true; END;
    ASSERT rejected,'capacity overflow was accepted';
    SET CONSTRAINTS ALL DEFERRED;
    replacement := public.issue_invitation(club_a,guest_session_id,now()+interval '1 day');
    SET LOCAL ROLE anon;
    PERFORM set_config('request.jwt.claim.sub','',true);
    rejected := false;
    BEGIN PERFORM public.guest_access('invite',invitation->>'token');
    EXCEPTION WHEN insufficient_privilege THEN rejected := true; END;
    ASSERT rejected,'revoked recruitment invite was accepted';
    output := public.guest_access('view',NULL,browser_token);
    ASSERT output ? 'participants','reissued invitation invalidated approved browser';
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub',owner_id::text,true);
    PERFORM public.league_command('revoke_guest',jsonb_build_object('session_id',guest_session_id,'participant_id',guest_id),gen_random_uuid());
    SET LOCAL ROLE anon;
    PERFORM set_config('request.jwt.claim.sub','',true);
    rejected := false;
    BEGIN PERFORM public.guest_access('view',NULL,browser_token);
    EXCEPTION WHEN insufficient_privilege THEN rejected := true; END;
    ASSERT rejected,'revoked guest retained access';

    SET LOCAL ROLE postgres;
    UPDATE private.guest_sessions SET expires_at=now()-interval '1 second' WHERE participant_id=guest_extra_id;
    UPDATE private.invitations SET expires_at=now()-interval '1 second' WHERE id=(replacement->>'invitation_id')::uuid;
    SET LOCAL ROLE anon;
    rejected := false;
    BEGIN PERFORM public.guest_access('view',NULL,extra_token);
    EXCEPTION WHEN insufficient_privilege THEN rejected := true; END;
    ASSERT rejected,'expired browser retained access';
    rejected := false;
    BEGIN PERFORM public.guest_access('invite',replacement->>'token');
    EXCEPTION WHEN insufficient_privilege THEN rejected := true; END;
    ASSERT rejected,'expired invitation was accepted';

    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub',owner_id::text,true);
    PERFORM public.league_command('revoke_invitation',jsonb_build_object('club_id',club_a,
        'invitation_id',replacement->>'invitation_id'),gen_random_uuid());
    SET LOCAL ROLE postgres;
    INSERT INTO public.clubs(name,status,legacy_id) VALUES ('Legacy assignment fixture','needs_owner',
        (SELECT COALESCE(min(legacy_id),0)-1 FROM public.clubs)) RETURNING id INTO result_id;
    SET LOCAL ROLE authenticated;
    rejected := false;
    BEGIN PERFORM private.assign_legacy_owner(result_id,owner_id);
    EXCEPTION WHEN insufficient_privilege THEN rejected := true; END;
    ASSERT rejected,'client could claim an unassigned legacy club';
    SET LOCAL ROLE postgres;
    PERFORM private.assign_legacy_owner(result_id,other_id);
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub',other_id::text,true);
    ASSERT EXISTS(SELECT 1 FROM public.clubs WHERE id=result_id),'assigned owner cannot read legacy club';
    PERFORM public.league_command('close_club',jsonb_build_object('club_id',result_id),gen_random_uuid());
    ASSERT (SELECT status FROM public.clubs WHERE id=result_id)='closed','explicit club closure failed';

    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.sub',owner_id::text,true);
    PERFORM public.league_command('leave_club',jsonb_build_object('club_id',club_b),gen_random_uuid());
    ASSERT EXISTS(SELECT 1 FROM public.clubs WHERE id=club_a),'leaving B removed A membership';
    ASSERT NOT EXISTS(SELECT 1 FROM public.clubs WHERE id=club_b),'left club still accessible';
    SET LOCAL ROLE postgres;
    SET CONSTRAINTS ALL IMMEDIATE;
    SET CONSTRAINTS ALL DEFERRED;
    DELETE FROM auth.users WHERE id=owner_id;
    ASSERT (SELECT status FROM public.clubs WHERE id=club_a)='closed','account deletion did not close owned club';
    ASSERT NOT EXISTS(SELECT 1 FROM public.club_participants WHERE club_id=club_a AND account_id=owner_id),'account link retained';
    ASSERT (SELECT display_name FROM public.club_participants WHERE id=participant_ids[1])='삭제된 참가자','participant not anonymized';
    ASSERT (SELECT count(*) FROM public.matches WHERE matches.session_id=session_id)=4,'account deletion removed shared matches';
    SET CONSTRAINTS ALL IMMEDIATE;
END;
$$;

SELECT 'PRD v0.3 regression assertions passed; fixtures rolled back' AS verification;
ROLLBACK;

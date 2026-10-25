--
--  20261019134950_prd_v03_hardening.sql
--  OurLeague
--
--  Created by 양호준 on 2026/10/19.
--

CREATE INDEX match_players_match_session_idx ON public.match_players(match_id,session_id);

DO $$
DECLARE table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY['Club','Club_Participants','Player','Game','GameByDay'] LOOP
        EXECUTE format('CREATE POLICY archive_denied ON public.%I AS RESTRICTIVE FOR ALL TO PUBLIC USING (false) WITH CHECK (false)',table_name);
    END LOOP;
    FOREACH table_name IN ARRAY ARRAY['invitations','guest_sessions','command_receipts'] LOOP
        EXECUTE format('CREATE POLICY server_only ON private.%I AS RESTRICTIVE FOR ALL TO PUBLIC USING (false) WITH CHECK (false)',table_name);
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION private.league_command(operation text, payload jsonb, request_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    actor uuid := auth.uid();
    payload_digest text;
    receipt private.command_receipts;
    club_row public.clubs;
    session_row public.sessions;
    match_row public.matches;
    participant_row public.session_participants;
    result_row public.results;
    invite_row private.invitations;
    target_id uuid;
    target_account uuid;
    target_participant uuid;
    output jsonb;
    previous_result jsonb;
    match_spec jsonb;
    player_id uuid;
    player_ids uuid[];
    selected_ids uuid[];
    appearance_counts jsonb := '{}'::jsonb;
    schedule jsonb := '[]'::jsonb;
    round_number integer;
    court_number integer;
    player_number integer;
    available_courts integer;
    new_version integer;
    seed_value bigint;
    role_owner boolean;
    expected_version integer;
    minimum_appearances integer;
    maximum_appearances integer;
BEGIN
    IF actor IS NULL OR request_id IS NULL OR operation IS NULL OR jsonb_typeof(payload) IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION 'authenticated_command_required' USING ERRCODE = '42501';
    END IF;
    payload_digest := encode(extensions.digest(payload::text, 'sha256'), 'hex');
    PERFORM pg_advisory_xact_lock(hashtextextended(actor::text || request_id::text, 0));
    SELECT * INTO receipt FROM private.command_receipts
        WHERE actor_id = actor AND command_receipts.request_id = league_command.request_id;
    IF FOUND THEN
        IF receipt.operation <> operation OR receipt.payload_hash <> payload_digest THEN
            RAISE EXCEPTION 'request_id_reused_with_different_command' USING ERRCODE = '23505';
        END IF;
        RETURN receipt.result;
    END IF;

    IF operation = 'create_club' THEN
        INSERT INTO public.clubs(name, description, owner_account_id)
            VALUES (payload->>'name', COALESCE(payload->>'description', ''), actor) RETURNING * INTO club_row;
        INSERT INTO public.memberships(club_id, account_id, role, status) VALUES (club_row.id, actor, 'owner', 'approved');
        output := to_jsonb(club_row);
    ELSIF operation = 'save_profile' THEN
        INSERT INTO public.profiles(id, display_name) VALUES (actor, payload->>'display_name')
            ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;
        output := jsonb_build_object('id', actor);
    ELSIF operation = 'request_membership' THEN
        SELECT * INTO invite_row FROM private.invitations WHERE kind = 'membership'
            AND token_hash = encode(extensions.digest(payload->>'token', 'sha256'), 'hex')
            AND revoked_at IS NULL AND expires_at > now();
        IF NOT FOUND THEN RAISE EXCEPTION 'invalid_invitation' USING ERRCODE = '42501'; END IF;
        SELECT * INTO club_row FROM public.clubs WHERE id = invite_row.club_id FOR UPDATE;
        IF club_row.status <> 'active' THEN RAISE EXCEPTION 'club_not_active'; END IF;
        IF NOT EXISTS (SELECT 1 FROM private.invitations WHERE id=invite_row.id AND revoked_at IS NULL AND expires_at>now()) THEN
            RAISE EXCEPTION 'invalid_invitation' USING ERRCODE='42501'; END IF;
        INSERT INTO public.memberships(club_id, account_id) VALUES (club_row.id, actor)
            ON CONFLICT (club_id, account_id) DO UPDATE SET status = CASE
                WHEN memberships.status = 'inactive' THEN 'pending' ELSE memberships.status END
            RETURNING id INTO target_id;
        output := jsonb_build_object('membership_id', target_id);
    ELSE
        IF operation IN ('save_club', 'close_club', 'revoke_invitation', 'approve_membership', 'save_participant', 'transfer_owner', 'leave_club', 'create_session') THEN
            SELECT * INTO club_row FROM public.clubs WHERE id = (payload->>'club_id')::uuid FOR UPDATE;
        ELSE
            IF operation IN ('start_match', 'save_result', 'abort_match', 'cancel_match', 'invalidate_result') THEN
                SELECT session_id INTO target_id FROM public.matches WHERE id = (payload->>'match_id')::uuid;
            ELSE target_id := (payload->>'session_id')::uuid; END IF;
            SELECT * INTO session_row FROM public.sessions WHERE id = target_id FOR UPDATE;
            IF NOT FOUND THEN RAISE EXCEPTION 'session_not_found' USING ERRCODE = '42501'; END IF;
            SELECT * INTO club_row FROM public.clubs WHERE id = session_row.club_id;
        END IF;
        IF club_row.id IS NULL OR club_row.status <> 'active' THEN
            RAISE EXCEPTION 'club_not_active_or_not_found' USING ERRCODE = '42501'; END IF;
        role_owner := club_row.owner_account_id = actor;
        IF operation NOT IN ('respond_attendance', 'leave_club') AND NOT role_owner THEN
            RAISE EXCEPTION 'owner_required' USING ERRCODE = '42501'; END IF;

        CASE operation
        WHEN 'save_club' THEN
            UPDATE public.clubs SET name = COALESCE(payload->>'name', name),
                description = COALESCE(payload->>'description', description) WHERE id = club_row.id RETURNING * INTO club_row;
            output := to_jsonb(club_row);
        WHEN 'revoke_invitation' THEN
            UPDATE private.invitations SET revoked_at=now() WHERE id=(payload->>'invitation_id')::uuid
                AND club_id=club_row.id RETURNING id INTO target_id;
            IF target_id IS NULL THEN RAISE EXCEPTION 'invitation_not_found'; END IF;
            output := jsonb_build_object('revoked',true);
        WHEN 'rename_court' THEN
            UPDATE public.session_courts SET name=payload->>'name' WHERE id=(payload->>'court_id')::uuid
                AND session_id=session_row.id RETURNING id INTO target_id;
            IF target_id IS NULL THEN RAISE EXCEPTION 'court_not_found'; END IF;
            output := jsonb_build_object('court_id',target_id);
        WHEN 'approve_membership' THEN
            UPDATE public.memberships SET status = 'approved'
                WHERE club_id = club_row.id AND id = (payload->>'membership_id')::uuid AND role = 'member'
                RETURNING id INTO target_id;
            IF target_id IS NULL THEN RAISE EXCEPTION 'membership_not_found'; END IF;
            output := jsonb_build_object('membership_id', target_id);
        WHEN 'close_club' THEN
            UPDATE public.matches SET status=CASE WHEN status='pending' THEN 'cancelled' ELSE 'aborted' END,
                finished_at=CASE WHEN status='in_progress' THEN now() ELSE finished_at END
                WHERE session_id IN (SELECT id FROM public.sessions WHERE club_id=club_row.id) AND status IN ('pending','in_progress');
            UPDATE public.sessions SET status='cancelled' WHERE club_id=club_row.id AND status NOT IN ('completed','cancelled');
            UPDATE private.invitations SET revoked_at=now() WHERE club_id=club_row.id AND revoked_at IS NULL;
            UPDATE private.guest_sessions SET revoked_at=now() WHERE participant_id IN (
                SELECT participant.id FROM public.session_participants participant JOIN public.sessions session
                    ON session.id=participant.session_id WHERE session.club_id=club_row.id);
            UPDATE public.clubs SET status='closed' WHERE id=club_row.id;
            output := jsonb_build_object('status','closed');
        WHEN 'transfer_owner' THEN
            target_account := (payload->>'account_id')::uuid;
            IF target_account = actor THEN RAISE EXCEPTION 'new_owner_required'; END IF;
            IF NOT EXISTS (SELECT 1 FROM public.memberships WHERE club_id = club_row.id
                AND account_id = target_account AND status = 'approved') THEN RAISE EXCEPTION 'approved_member_required'; END IF;
            UPDATE public.memberships SET role = 'member' WHERE club_id = club_row.id AND account_id = actor;
            UPDATE public.memberships SET role = 'owner' WHERE club_id = club_row.id AND account_id = target_account;
            UPDATE public.clubs SET owner_account_id = target_account WHERE id = club_row.id;
            output := jsonb_build_object('owner_account_id', target_account);
        WHEN 'leave_club' THEN
            IF role_owner THEN RAISE EXCEPTION 'transfer_or_close_club_first'; END IF;
            UPDATE public.memberships SET status = 'inactive' WHERE club_id = club_row.id AND account_id = actor;
            UPDATE public.club_participants SET account_id = NULL WHERE club_id = club_row.id AND account_id = actor;
            UPDATE public.session_participants SET account_id = NULL WHERE account_id = actor
                AND session_id IN (SELECT id FROM public.sessions WHERE club_id = club_row.id);
            output := jsonb_build_object('left', true);
        WHEN 'save_participant' THEN
            target_account := (payload->>'account_id')::uuid;
            IF target_account IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.memberships
                WHERE club_id = club_row.id AND account_id = target_account AND status = 'approved') THEN
                RAISE EXCEPTION 'approved_account_link_required'; END IF;
            IF payload->>'participant_id' IS NULL THEN
                INSERT INTO public.club_participants(club_id, account_id, display_name, label)
                    VALUES (club_row.id, target_account, payload->>'display_name', payload->>'label') RETURNING id INTO target_id;
            ELSE
                UPDATE public.club_participants SET display_name = COALESCE(payload->>'display_name', display_name),
                    label = CASE WHEN payload ? 'label' THEN payload->>'label' ELSE label END,
                    is_active = COALESCE((payload->>'is_active')::boolean, is_active),
                    account_id = CASE WHEN payload ? 'account_id' THEN target_account ELSE account_id END
                    WHERE id = (payload->>'participant_id')::uuid AND club_id = club_row.id RETURNING id INTO target_id;
                IF target_id IS NULL THEN RAISE EXCEPTION 'participant_not_found'; END IF;
                UPDATE public.session_participants SET account_id = (SELECT account_id FROM public.club_participants WHERE id = target_id)
                    WHERE club_participant_id = target_id;
                UPDATE public.sessions SET roster_version = roster_version + 1, schedule_stale = true
                    WHERE club_id = club_row.id AND status IN ('recruiting', 'confirmed', 'in_progress')
                      AND EXISTS (SELECT 1 FROM public.session_participants WHERE session_id = sessions.id AND club_participant_id = target_id);
            END IF;
            output := jsonb_build_object('participant_id', target_id);
        WHEN 'create_session' THEN
            INSERT INTO public.sessions(club_id,title,starts_at,ends_at,location,capacity,court_count,round_count,attendance_deadline,notice)
                VALUES (club_row.id,payload->>'title',(payload->>'starts_at')::timestamptz,(payload->>'ends_at')::timestamptz,
                    payload->>'location',COALESCE((payload->>'capacity')::int,16),COALESCE((payload->>'court_count')::int,1),
                    COALESCE((payload->>'round_count')::int,3),(payload->>'attendance_deadline')::timestamptz,COALESCE(payload->>'notice',''))
                RETURNING * INTO session_row;
            INSERT INTO public.session_courts(session_id,name,position)
                SELECT session_row.id,'코트 ' || position,position FROM generate_series(1,session_row.court_count) position;
            output := to_jsonb(session_row);
        WHEN 'update_session' THEN
            IF session_row.status NOT IN ('needs_review', 'recruiting', 'confirmed') OR EXISTS (
                SELECT 1 FROM public.matches WHERE session_id = session_row.id AND started_at IS NOT NULL) THEN
                RAISE EXCEPTION 'session_configuration_locked'; END IF;
            IF (payload->>'expected_roster_version')::int IS DISTINCT FROM session_row.roster_version THEN
                RAISE EXCEPTION 'stale_roster_version' USING ERRCODE = '40001'; END IF;
            IF payload ? 'court_count' THEN
                IF (payload->>'court_count')::int NOT BETWEEN 1 AND 4 THEN RAISE EXCEPTION 'court_count_out_of_range'; END IF;
                UPDATE public.matches SET status='cancelled' WHERE session_id=session_row.id AND status='pending';
                UPDATE public.session_courts SET is_active=position<=(payload->>'court_count')::int WHERE session_id=session_row.id;
                INSERT INTO public.session_courts(session_id,name,position)
                    SELECT session_row.id,'코트 ' || position,position FROM generate_series(1,(payload->>'court_count')::int) position
                    ON CONFLICT (session_id,position) DO NOTHING;
            END IF;
            UPDATE public.sessions SET title = COALESCE(payload->>'title',title),
                starts_at = COALESCE((payload->>'starts_at')::timestamptz,starts_at),
                ends_at = COALESCE((payload->>'ends_at')::timestamptz,ends_at),
                attendance_deadline = COALESCE((payload->>'attendance_deadline')::timestamptz,attendance_deadline),
                location = COALESCE(payload->>'location',location),notice = COALESCE(payload->>'notice',notice),
                capacity = COALESCE((payload->>'capacity')::int,capacity),round_count = COALESCE((payload->>'round_count')::int,round_count),
                court_count = COALESCE((payload->>'court_count')::int,court_count),
                roster_version = roster_version + 1,schedule_stale = true,
                status = CASE WHEN status = 'needs_review' THEN 'recruiting' ELSE status END
                WHERE id = session_row.id RETURNING * INTO session_row;
            output := to_jsonb(session_row);
        WHEN 'respond_attendance' THEN
            IF session_row.status NOT IN ('recruiting','confirmed','in_progress') THEN RAISE EXCEPTION 'attendance_closed'; END IF;
            IF NOT role_owner AND (session_row.attendance_deadline <= now() OR NOT private.can_read_club(club_row.id)) THEN
                RAISE EXCEPTION 'attendance_permission_denied' USING ERRCODE = '42501'; END IF;
            IF role_owner THEN target_participant := (payload->>'club_participant_id')::uuid;
            ELSE
                SELECT id INTO target_participant FROM public.club_participants
                    WHERE club_id = club_row.id AND account_id = actor AND is_active;
            END IF;
            IF NOT EXISTS (SELECT 1 FROM public.club_participants WHERE id = target_participant AND club_id = club_row.id AND is_active) THEN
                RAISE EXCEPTION 'active_club_participant_required'; END IF;
            INSERT INTO public.session_participants(session_id,club_participant_id,account_id,display_name,response,approval)
                SELECT session_row.id,id,account_id,display_name,payload->>'response','approved'
                FROM public.club_participants WHERE id = target_participant
                ON CONFLICT (session_id,club_participant_id) DO UPDATE SET response = EXCLUDED.response
                RETURNING * INTO participant_row;
            output := to_jsonb(participant_row);
        WHEN 'approve_guest' THEN
            IF session_row.status NOT IN ('recruiting','confirmed','in_progress') THEN RAISE EXCEPTION 'attendance_closed'; END IF;
            UPDATE public.session_participants SET approval = payload->>'approval'
                WHERE id = (payload->>'participant_id')::uuid AND session_id = session_row.id RETURNING * INTO participant_row;
            IF NOT FOUND THEN RAISE EXCEPTION 'participant_not_found'; END IF;
            output := to_jsonb(participant_row);
        WHEN 'link_guest' THEN
            IF session_row.status IN ('completed','cancelled') THEN RAISE EXCEPTION 'attendance_closed'; END IF;
            SELECT id,account_id INTO target_participant,target_account FROM public.club_participants
                WHERE id=(payload->>'club_participant_id')::uuid AND club_id=club_row.id AND is_active;
            IF target_participant IS NULL THEN RAISE EXCEPTION 'active_club_participant_required'; END IF;
            UPDATE public.session_participants SET club_participant_id=target_participant,account_id=target_account
                WHERE id=(payload->>'participant_id')::uuid AND session_id=session_row.id AND club_participant_id IS NULL
                RETURNING * INTO participant_row;
            IF NOT FOUND THEN RAISE EXCEPTION 'unlinked_guest_required'; END IF;
            output := to_jsonb(participant_row);
        WHEN 'preview_schedule' THEN
            IF session_row.status NOT IN ('recruiting','confirmed') THEN RAISE EXCEPTION 'preview_requires_unstarted_session'; END IF;
            SELECT array_agg(id ORDER BY id) INTO player_ids FROM public.session_participants participant
                WHERE session_id = session_row.id AND response = 'attending' AND approval = 'approved'
                AND (club_participant_id IS NULL OR EXISTS (SELECT 1 FROM public.club_participants
                    WHERE id = participant.club_participant_id AND is_active));
            IF COALESCE(cardinality(player_ids),0) < 4 THEN RAISE EXCEPTION 'at_least_four_players_required'; END IF;
            available_courts := least(session_row.court_count, cardinality(player_ids)/4);
            seed_value := COALESCE((payload->>'seed')::bigint,0);
            FOR round_number IN 1..session_row.round_count LOOP
                SELECT array_agg(candidate.id ORDER BY candidate.played,candidate.tie_break) INTO selected_ids FROM (
                    SELECT participant_id AS id,COALESCE((appearance_counts->>participant_id::text)::int,0) AS played,
                        md5(seed_value::text || ':' || round_number::text || ':' || participant_id::text) AS tie_break
                    FROM unnest(player_ids) participant_id ORDER BY played,tie_break LIMIT available_courts*4) candidate;
                FOR court_number IN 1..available_courts LOOP
                    SELECT id INTO target_id FROM public.session_courts WHERE session_id = session_row.id AND position = court_number AND is_active;
                    schedule := schedule || jsonb_build_array(jsonb_build_object('round_index',round_number,'court_id',target_id,
                        'team_a',selected_ids[(court_number-1)*4+1:(court_number-1)*4+2],
                        'team_b',selected_ids[(court_number-1)*4+3:(court_number-1)*4+4]));
                END LOOP;
                FOREACH player_id IN ARRAY selected_ids LOOP
                    appearance_counts := jsonb_set(appearance_counts,ARRAY[player_id::text],
                        to_jsonb(COALESCE((appearance_counts->>player_id::text)::int,0)+1));
                END LOOP;
            END LOOP;
            output := jsonb_build_object('matches',schedule,'appearances',appearance_counts,'seed',seed_value,
                'roster_version',session_row.roster_version,'schedule_version',session_row.schedule_version);
        WHEN 'confirm_schedule' THEN
            IF session_row.status NOT IN ('recruiting','confirmed','in_progress') THEN RAISE EXCEPTION 'schedule_locked'; END IF;
            IF (payload->>'expected_roster_version')::int IS DISTINCT FROM session_row.roster_version OR
                (payload->>'expected_schedule_version')::int IS DISTINCT FROM session_row.schedule_version THEN
                RAISE EXCEPTION 'stale_schedule_version' USING ERRCODE = '40001'; END IF;
            IF jsonb_typeof(payload->'matches') IS DISTINCT FROM 'array' OR jsonb_array_length(payload->'matches') = 0 THEN
                RAISE EXCEPTION 'nonempty_schedule_required'; END IF;
            IF session_row.status<>'in_progress' AND jsonb_array_length(payload->'matches')<>(
                SELECT least(session_row.court_count,count(*)::int/4)*session_row.round_count
                    FROM public.session_participants participant WHERE session_id=session_row.id AND approval='approved'
                    AND response='attending' AND (club_participant_id IS NULL OR EXISTS (
                        SELECT 1 FROM public.club_participants WHERE id=participant.club_participant_id AND is_active))) THEN
                RAISE EXCEPTION 'schedule_slot_count_mismatch'; END IF;
            new_version := session_row.schedule_version + 1;
            UPDATE public.matches SET status = 'cancelled' WHERE session_id = session_row.id AND status = 'pending';
            FOR match_spec IN SELECT value FROM jsonb_array_elements(payload->'matches') LOOP
                IF jsonb_array_length(match_spec->'team_a') IS DISTINCT FROM 2 OR
                    jsonb_array_length(match_spec->'team_b') IS DISTINCT FROM 2 THEN RAISE EXCEPTION 'two_players_per_team_required'; END IF;
                IF (match_spec->>'round_index')::int > session_row.round_count THEN RAISE EXCEPTION 'round_out_of_range'; END IF;
                IF NOT EXISTS (SELECT 1 FROM public.session_courts WHERE id=(match_spec->>'court_id')::uuid
                    AND session_id=session_row.id AND is_active) THEN RAISE EXCEPTION 'active_court_required'; END IF;
                INSERT INTO public.matches(session_id,round_index,court_id,schedule_version)
                    VALUES (session_row.id,(match_spec->>'round_index')::int,(match_spec->>'court_id')::uuid,new_version)
                    RETURNING id INTO target_id;
                FOR player_number IN 0..3 LOOP
                    player_id := (CASE WHEN player_number < 2 THEN match_spec->'team_a'->>player_number
                        ELSE match_spec->'team_b'->>(player_number-2) END)::uuid;
                    IF NOT EXISTS (SELECT 1 FROM public.session_participants participant WHERE id = player_id AND session_id = session_row.id
                        AND response = 'attending' AND approval = 'approved' AND (club_participant_id IS NULL OR EXISTS (
                            SELECT 1 FROM public.club_participants WHERE id = participant.club_participant_id AND is_active))) THEN
                        RAISE EXCEPTION 'approved_active_player_required'; END IF;
                    INSERT INTO public.match_players(match_id,session_id,participant_id,team,slot)
                        VALUES (target_id,session_row.id,player_id,CASE WHEN player_number<2 THEN 'a' ELSE 'b' END,player_number%2+1);
                END LOOP;
            END LOOP;
            SELECT min(played),max(played) INTO minimum_appearances,maximum_appearances FROM (
                SELECT count(match.id)::int AS played FROM public.session_participants participant
                LEFT JOIN public.match_players player ON player.participant_id=participant.id
                LEFT JOIN public.matches match ON match.id=player.match_id AND match.status<>'cancelled'
                WHERE participant.session_id=session_row.id AND participant.approval='approved' AND participant.response='attending'
                    AND (participant.club_participant_id IS NULL OR EXISTS (SELECT 1 FROM public.club_participants
                        WHERE id=participant.club_participant_id AND is_active))
                GROUP BY participant.id) counts;
            IF maximum_appearances-minimum_appearances>1 AND NOT COALESCE((payload->>'accept_unequal')::boolean,false) THEN
                RAISE EXCEPTION 'unequal_schedule_requires_acknowledgment'; END IF;
            UPDATE public.sessions SET schedule_version = new_version,schedule_stale = false,
                status = CASE WHEN status = 'in_progress' THEN status ELSE 'confirmed' END,seed = (payload->>'seed')::bigint
                WHERE id = session_row.id;
            output := jsonb_build_object('schedule_version',new_version,'minimum_appearances',minimum_appearances,
                'maximum_appearances',maximum_appearances,'fairness_warning',maximum_appearances-minimum_appearances>1);
        WHEN 'start_match' THEN
            IF session_row.status NOT IN ('confirmed','in_progress') OR session_row.schedule_stale THEN RAISE EXCEPTION 'schedule_not_ready'; END IF;
            IF (payload->>'expected_schedule_version')::int IS DISTINCT FROM session_row.schedule_version THEN
                RAISE EXCEPTION 'stale_schedule_version' USING ERRCODE = '40001'; END IF;
            SELECT * INTO match_row FROM public.matches WHERE id = (payload->>'match_id')::uuid FOR UPDATE;
            IF match_row.status <> 'pending' OR match_row.court_id IS NULL THEN RAISE EXCEPTION 'match_not_startable'; END IF;
            IF EXISTS (SELECT 1 FROM public.matches WHERE session_id = session_row.id AND court_id = match_row.court_id
                AND (status = 'in_progress' OR (status = 'pending' AND round_index < match_row.round_index))) THEN
                RAISE EXCEPTION 'court_busy_or_prior_match_pending'; END IF;
            IF EXISTS (SELECT 1 FROM public.match_players player JOIN public.session_participants participant ON participant.id = player.participant_id
                WHERE player.match_id = match_row.id AND (participant.response <> 'attending' OR participant.approval <> 'approved' OR
                    (participant.club_participant_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.club_participants
                        WHERE id = participant.club_participant_id AND is_active)))) THEN RAISE EXCEPTION 'player_no_longer_eligible'; END IF;
            IF EXISTS (SELECT 1 FROM public.match_players next_player JOIN public.match_players active_player
                ON active_player.participant_id = next_player.participant_id JOIN public.matches active_match ON active_match.id = active_player.match_id
                WHERE next_player.match_id = match_row.id AND active_match.status = 'in_progress') THEN
                RAISE EXCEPTION 'participant_already_playing'; END IF;
            UPDATE public.matches SET status = 'in_progress',started_at = now() WHERE id = match_row.id;
            UPDATE public.sessions SET status = 'in_progress' WHERE id = session_row.id;
            output := jsonb_build_object('match_id',match_row.id,'status','in_progress');
        WHEN 'save_result' THEN
            SELECT * INTO match_row FROM public.matches WHERE id = (payload->>'match_id')::uuid FOR UPDATE;
            IF match_row.status NOT IN ('in_progress','completed') THEN RAISE EXCEPTION 'match_not_recordable'; END IF;
            SELECT * INTO result_row FROM public.results WHERE match_id = match_row.id;
            expected_version := COALESCE(result_row.version,0);
            IF (payload->>'expected_result_version')::int IS DISTINCT FROM expected_version THEN
                RAISE EXCEPTION 'stale_result_version' USING ERRCODE = '40001'; END IF;
            IF expected_version > 0 AND COALESCE(char_length(btrim(payload->>'reason')),0)=0 THEN RAISE EXCEPTION 'correction_reason_required'; END IF;
            previous_result := CASE WHEN expected_version>0 THEN to_jsonb(result_row) ELSE NULL END;
            INSERT INTO public.results(match_id,winner,score_a,score_b,version)
                VALUES (match_row.id,payload->>'winner',(payload->>'score_a')::int,(payload->>'score_b')::int,expected_version+1)
                ON CONFLICT (match_id) DO UPDATE SET winner=EXCLUDED.winner,score_a=EXCLUDED.score_a,score_b=EXCLUDED.score_b,
                    version=EXCLUDED.version,is_valid=true,updated_at=now() RETURNING * INTO result_row;
            UPDATE public.matches SET status='completed',finished_at=COALESCE(finished_at,now()) WHERE id=match_row.id;
            INSERT INTO public.result_revisions(match_id,old_result,new_result,reason,actor_account_id)
                VALUES (match_row.id,previous_result,to_jsonb(result_row),COALESCE(NULLIF(btrim(payload->>'reason'),''),'initial_result'),actor);
            output := to_jsonb(result_row);
        WHEN 'invalidate_result' THEN
            IF COALESCE(char_length(btrim(payload->>'reason')),0)=0 THEN RAISE EXCEPTION 'invalidation_reason_required'; END IF;
            SELECT * INTO result_row FROM public.results WHERE match_id = (payload->>'match_id')::uuid FOR UPDATE;
            IF NOT FOUND OR NOT result_row.is_valid THEN RAISE EXCEPTION 'valid_result_required'; END IF;
            IF (payload->>'expected_result_version')::int IS DISTINCT FROM result_row.version THEN
                RAISE EXCEPTION 'stale_result_version' USING ERRCODE = '40001'; END IF;
            previous_result := to_jsonb(result_row);
            UPDATE public.results SET is_valid=false,version=version+1,updated_at=now()
                WHERE match_id=result_row.match_id RETURNING * INTO result_row;
            UPDATE public.matches SET status='aborted' WHERE id=result_row.match_id;
            INSERT INTO public.result_revisions(match_id,old_result,new_result,reason,actor_account_id)
                VALUES (result_row.match_id,previous_result,to_jsonb(result_row),payload->>'reason',actor);
            output := to_jsonb(result_row);
        WHEN 'abort_match', 'cancel_match' THEN
            UPDATE public.matches SET status=CASE WHEN operation='abort_match' THEN 'aborted' ELSE 'cancelled' END,
                finished_at=CASE WHEN operation='abort_match' THEN now() ELSE NULL END
                WHERE id=(payload->>'match_id')::uuid AND status=CASE WHEN operation='abort_match' THEN 'in_progress' ELSE 'pending' END
                RETURNING id INTO target_id;
            IF target_id IS NULL THEN RAISE EXCEPTION 'invalid_match_transition'; END IF;
            output := jsonb_build_object('match_id',target_id);
        WHEN 'complete_session' THEN
            IF session_row.status NOT IN ('confirmed','in_progress') OR EXISTS (SELECT 1 FROM public.matches
                WHERE session_id=session_row.id AND status IN ('pending','in_progress')) THEN RAISE EXCEPTION 'unfinished_session'; END IF;
            UPDATE public.sessions SET status='completed' WHERE id=session_row.id;
            UPDATE private.invitations SET revoked_at=now() WHERE session_id=session_row.id AND revoked_at IS NULL;
            output := jsonb_build_object('status','completed');
        WHEN 'cancel_session' THEN
            IF session_row.status IN ('completed','cancelled') THEN RAISE EXCEPTION 'session_already_terminal'; END IF;
            UPDATE public.matches SET status=CASE WHEN status='pending' THEN 'cancelled' ELSE 'aborted' END,
                finished_at=CASE WHEN status='in_progress' THEN now() ELSE finished_at END
                WHERE session_id=session_row.id AND status IN ('pending','in_progress');
            UPDATE public.sessions SET status='cancelled' WHERE id=session_row.id;
            UPDATE private.invitations SET revoked_at=now() WHERE session_id=session_row.id AND revoked_at IS NULL;
            output := jsonb_build_object('status','cancelled');
        WHEN 'revoke_guest' THEN
            UPDATE private.guest_sessions SET revoked_at=now() WHERE participant_id=(payload->>'participant_id')::uuid
                AND participant_id IN (SELECT id FROM public.session_participants WHERE session_id=session_row.id);
            output := jsonb_build_object('revoked',true);
        ELSE RAISE EXCEPTION 'unsupported_operation';
        END CASE;
    END IF;
    INSERT INTO private.command_receipts(actor_id,request_id,operation,payload_hash,result)
        VALUES (actor,request_id,operation,payload_digest,output);
    RETURN output;
END;
$$;

CREATE OR REPLACE FUNCTION private.guest_access(action text, invite_token text, browser_token text, display_name text, response text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE invite_row private.invitations; guest_row private.guest_sessions; participant_row public.session_participants;
    session_row public.sessions; browser_hash text; output jsonb;
BEGIN
    IF action NOT IN ('invite','submit','view') OR action IS NULL THEN RAISE EXCEPTION 'invalid_guest_action'; END IF;
    IF action IN ('invite','submit') THEN
        SELECT * INTO invite_row FROM private.invitations WHERE kind='guest'
            AND token_hash=encode(extensions.digest(invite_token,'sha256'),'hex') AND expires_at>now() AND revoked_at IS NULL;
        IF NOT FOUND THEN RAISE EXCEPTION 'invalid_invitation' USING ERRCODE='42501'; END IF;
        SELECT * INTO session_row FROM public.sessions WHERE id=invite_row.session_id FOR UPDATE;
        IF NOT EXISTS (SELECT 1 FROM private.invitations WHERE id=invite_row.id AND revoked_at IS NULL AND expires_at>now()) THEN
            RAISE EXCEPTION 'invalid_invitation' USING ERRCODE='42501'; END IF;
        IF session_row.status NOT IN ('recruiting','confirmed') OR session_row.attendance_deadline<=now()
            OR NOT EXISTS (SELECT 1 FROM public.clubs WHERE id=session_row.club_id AND status='active') THEN
            RAISE EXCEPTION 'invitation_closed' USING ERRCODE='42501'; END IF;
    END IF;
    IF action='submit' THEN
        IF browser_token IS NULL OR browser_token !~ '^[0-9a-f]{64}$' OR browser_token=invite_token THEN
            RAISE EXCEPTION 'independent_random_browser_token_required'; END IF;
        IF char_length(btrim(display_name)) NOT BETWEEN 2 AND 20 OR display_name IS NULL OR response IS NULL
            OR response NOT IN ('attending','declined') THEN RAISE EXCEPTION 'invalid_guest_response'; END IF;
        browser_hash := encode(extensions.digest(browser_token,'sha256'),'hex');
        PERFORM pg_advisory_xact_lock(hashtextextended(browser_hash,0));
        SELECT * INTO guest_row FROM private.guest_sessions WHERE token_hash=browser_hash;
        IF FOUND THEN
            SELECT * INTO participant_row FROM public.session_participants WHERE id=guest_row.participant_id;
            IF guest_row.revoked_at IS NOT NULL OR guest_row.expires_at<=now() OR participant_row.session_id<>session_row.id THEN
                RAISE EXCEPTION 'guest_session_expired_or_wrong_session' USING ERRCODE='42501'; END IF;
            UPDATE public.session_participants SET display_name=btrim(guest_access.display_name),response=guest_access.response
                WHERE id=participant_row.id RETURNING * INTO participant_row;
        ELSE
            INSERT INTO public.session_participants(session_id,display_name,response)
                VALUES (session_row.id,btrim(display_name),response) RETURNING * INTO participant_row;
            INSERT INTO private.guest_sessions(invitation_id,participant_id,token_hash,expires_at)
                VALUES (invite_row.id,participant_row.id,browser_hash,session_row.ends_at+interval '7 days') RETURNING * INTO guest_row;
        END IF;
    ELSIF action='view' THEN
        SELECT * INTO guest_row FROM private.guest_sessions WHERE token_hash=encode(extensions.digest(browser_token,'sha256'),'hex')
            AND revoked_at IS NULL AND expires_at>now();
        IF NOT FOUND THEN RAISE EXCEPTION 'invalid_guest_session' USING ERRCODE='42501'; END IF;
        SELECT * INTO participant_row FROM public.session_participants WHERE id=guest_row.participant_id;
        SELECT * INTO session_row FROM public.sessions WHERE id=participant_row.session_id;
        IF NOT EXISTS (SELECT 1 FROM public.clubs WHERE id=session_row.club_id AND status='active') THEN
            RAISE EXCEPTION 'club_not_active' USING ERRCODE='42501'; END IF;
    END IF;
    output := jsonb_build_object('session',jsonb_build_object('id',session_row.id,'title',session_row.title,
        'starts_at',session_row.starts_at,'ends_at',session_row.ends_at,'location',session_row.location,
        'notice',session_row.notice,'status',session_row.status));
    IF action<>'invite' THEN
        output := output || jsonb_build_object('self',jsonb_build_object('id',participant_row.id,
            'display_name',participant_row.display_name,'response',participant_row.response,'approval',participant_row.approval));
    END IF;
    IF participant_row.approval='approved' AND participant_row.response='attending' THEN
        output := output || jsonb_build_object('participants',(SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id',id,'display_name',participant.display_name)),'[]'::jsonb) FROM public.session_participants participant
            WHERE session_id=session_row.id AND approval='approved' AND participant.response='attending'),
            'courts',(SELECT COALESCE(jsonb_agg(to_jsonb(court)),'[]'::jsonb) FROM public.session_courts court WHERE session_id=session_row.id),
            'matches',(SELECT COALESCE(jsonb_agg(to_jsonb(match)),'[]'::jsonb) FROM public.matches match WHERE session_id=session_row.id),
            'players',(SELECT COALESCE(jsonb_agg(to_jsonb(player)),'[]'::jsonb) FROM public.match_players player WHERE session_id=session_row.id),
            'results',(SELECT COALESCE(jsonb_agg(to_jsonb(result)),'[]'::jsonb) FROM public.results result JOIN public.matches match
                ON match.id=result.match_id WHERE match.session_id=session_row.id));
    END IF;
    RETURN output;
END;
$$;


CREATE FUNCTION private.assign_legacy_owner(target_club uuid, account_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
BEGIN
    PERFORM 1 FROM public.clubs WHERE id=target_club AND status='needs_owner' AND legacy_id IS NOT NULL FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'unassigned_legacy_club_required'; END IF;
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id=account_id) THEN RAISE EXCEPTION 'existing_auth_account_required'; END IF;
    INSERT INTO public.memberships(club_id,account_id,role,status) VALUES (target_club,account_id,'owner','approved');
    UPDATE public.clubs SET owner_account_id=account_id,status='active' WHERE id=target_club;
END;
$$;
REVOKE ALL ON FUNCTION private.assign_legacy_owner(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

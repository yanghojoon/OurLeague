--
--  20261019134419_prd_v03_legacy_import.sql
--  OurLeague
--
--  Created by 양호준 on 2026/10/19.
--

DO $$
DECLARE day_row public."GameByDay"; candidate_clubs bigint[]; target_session uuid; target_club uuid;
BEGIN
    IF EXISTS (SELECT 1 FROM public."Game" game WHERE cardinality(team_a) IS DISTINCT FROM 2
        OR cardinality(team_b) IS DISTINCT FROM 2 OR
        (SELECT count(DISTINCT player_id) FROM unnest(team_a || team_b) player_id) <> 4 OR
        EXISTS (SELECT 1 FROM unnest(team_a || team_b) player_id WHERE NOT EXISTS (
            SELECT 1 FROM public."Player" WHERE id=player_id))) THEN
        RAISE EXCEPTION 'legacy_game_player_validation_failed'; END IF;
    IF EXISTS (SELECT 1 FROM public."Game" game WHERE (SELECT count(*) FROM public."GameByDay" day
        WHERE game.id=ANY(day.games))<>1) THEN RAISE EXCEPTION 'legacy_game_session_mapping_ambiguous'; END IF;

    INSERT INTO public.clubs(name,status,legacy_id) SELECT name,'needs_owner',id FROM public."Club";
    INSERT INTO public.club_participants(club_id,display_name,legacy_player_id,created_at)
        SELECT club.id,player.name,player.id,player.created_at FROM public."Club_Participants" membership
        JOIN public."Player" player ON player.id=membership.player_id
        JOIN public.clubs club ON club.legacy_id=membership.club_id;

    FOR day_row IN SELECT * FROM public."GameByDay" LOOP
        SELECT array_agg(candidate.id) INTO candidate_clubs FROM (
            SELECT club.id FROM public."Club" club WHERE NOT EXISTS (
                SELECT 1 FROM public."Game" game CROSS JOIN LATERAL unnest(game.team_a || game.team_b) player_id
                WHERE game.id=ANY(day_row.games) AND NOT EXISTS (
                    SELECT 1 FROM public."Club_Participants" participant
                    WHERE participant.club_id=club.id AND participant.player_id=player_id))) candidate;
        IF cardinality(candidate_clubs) IS DISTINCT FROM 1 THEN
            RAISE EXCEPTION 'legacy_session_club_mapping_ambiguous'; END IF;
        SELECT id INTO target_club FROM public.clubs WHERE legacy_id=candidate_clubs[1];
        INSERT INTO public.sessions(club_id,title,status,legacy_id,legacy_start_date,legacy_end_date)
            VALUES (target_club,COALESCE(NULLIF(btrim(day_row.name),''),'기존 모임 (검토 필요)'),
                'needs_review',day_row.id,day_row.started_at,day_row.ended_at) RETURNING id INTO target_session;
        INSERT INTO public.session_courts(session_id,name,position) VALUES (target_session,'코트 미확인',1);
        INSERT INTO public.session_participants(session_id,club_participant_id,display_name,response,approval)
            SELECT DISTINCT target_session,participant.id,participant.display_name,'attending','approved'
            FROM public."Game" game CROSS JOIN LATERAL unnest(game.team_a || game.team_b) player_id
            JOIN public.club_participants participant ON participant.club_id=target_club AND participant.legacy_player_id=player_id
            WHERE game.id=ANY(day_row.games);
        INSERT INTO public.matches(session_id,schedule_version,legacy_id,created_at)
            SELECT target_session,0,id,created_at FROM public."Game" WHERE id=ANY(day_row.games);
        INSERT INTO public.match_players(match_id,session_id,participant_id,team,slot)
            SELECT match.id,target_session,attendance.id,team.name,player.position::int
            FROM public."Game" game JOIN public.matches match ON match.legacy_id=game.id
            CROSS JOIN LATERAL (VALUES ('a',game.team_a),('b',game.team_b)) team(name,ids)
            CROSS JOIN LATERAL unnest(team.ids) WITH ORDINALITY player(id,position)
            JOIN public.club_participants participant ON participant.club_id=target_club AND participant.legacy_player_id=player.id
            JOIN public.session_participants attendance ON attendance.session_id=target_session AND attendance.club_participant_id=participant.id
            WHERE game.id=ANY(day_row.games);
    END LOOP;

    INSERT INTO public.results(match_id,winner,score_a,score_b)
        SELECT match.id,CASE WHEN game.score[1]>game.score[2] THEN 'a' ELSE 'b' END,game.score[1]::int,game.score[2]::int
        FROM public."Game" game JOIN public.matches match ON match.legacy_id=game.id
        WHERE cardinality(game.score)=2 AND game.score[1]>=0 AND game.score[2]>=0 AND game.score[1]<>game.score[2];
    UPDATE public.matches SET status='completed' WHERE id IN (SELECT match_id FROM public.results);
    INSERT INTO public.result_revisions(match_id,new_result,reason)
        SELECT match_id,to_jsonb(result),'legacy_score_import' FROM public.results result;
END;
$$;

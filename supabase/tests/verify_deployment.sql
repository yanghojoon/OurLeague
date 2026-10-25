--
--  verify_deployment.sql
--  OurLeague
--
--  Created by 양호준 on 2026/10/19.
--

SELECT 'clubs' AS entity, count(*) AS legacy_rows,
    count(migrated.id) AS mapped_rows FROM public."Club" legacy LEFT JOIN public.clubs migrated ON migrated.legacy_id=legacy.id
UNION ALL SELECT 'club_participants',count(*),count(migrated.id) FROM public."Club_Participants" legacy
    LEFT JOIN public.clubs club ON club.legacy_id=legacy.club_id
    LEFT JOIN public.club_participants migrated ON migrated.club_id=club.id AND migrated.legacy_player_id=legacy.player_id
UNION ALL SELECT 'sessions',count(*),count(migrated.id) FROM public."GameByDay" legacy
    LEFT JOIN public.sessions migrated ON migrated.legacy_id=legacy.id
UNION ALL SELECT 'matches',count(*),count(migrated.id) FROM public."Game" legacy
    LEFT JOIN public.matches migrated ON migrated.legacy_id=legacy.id;

SELECT
    (SELECT count(*) FROM public.matches WHERE legacy_id IS NOT NULL) AS imported_matches,
    (SELECT count(*) FROM public.results result JOIN public.matches match ON match.id=result.match_id
        WHERE match.legacy_id IS NOT NULL AND result.is_valid) AS imported_results,
    (SELECT count(*) FROM public.clubs WHERE status='needs_owner') AS clubs_needing_owner,
    (SELECT count(*) FROM public.sessions WHERE status='needs_review') AS sessions_needing_review;

SELECT count(*) AS legacy_team_mismatches FROM public.matches match JOIN public."Game" legacy ON legacy.id=match.legacy_id
WHERE legacy.team_a IS DISTINCT FROM (SELECT array_agg(participant.legacy_player_id ORDER BY player.slot)
    FROM public.match_players player JOIN public.session_participants attendance ON attendance.id=player.participant_id
    JOIN public.club_participants participant ON participant.id=attendance.club_participant_id WHERE player.match_id=match.id AND player.team='a')
OR legacy.team_b IS DISTINCT FROM (SELECT array_agg(participant.legacy_player_id ORDER BY player.slot)
    FROM public.match_players player JOIN public.session_participants attendance ON attendance.id=player.participant_id
    JOIN public.club_participants participant ON participant.id=attendance.club_participant_id WHERE player.match_id=match.id AND player.team='b');

SELECT table_schema,table_name,grantee,privilege_type FROM information_schema.role_table_grants
WHERE (table_schema='private' OR (table_schema='public' AND table_name IN
    ('Club','Club_Participants','Player','Game','GameByDay','player_stats')))
AND grantee IN ('anon','authenticated');

SELECT viewname FROM pg_views WHERE schemaname='public' AND viewname IN ('player_stats','participant_stats')
AND NOT EXISTS (SELECT 1 FROM pg_class relation JOIN pg_namespace namespace ON namespace.oid=relation.relnamespace
    WHERE namespace.nspname='public' AND relation.relname=viewname AND 'security_invoker=true'=ANY(relation.reloptions));

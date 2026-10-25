--
--  prd_v03_schedule_properties.sql
--  OurLeague
--
--  Created by 양호준 on 2026/10/19.
--

BEGIN;

DO $$
DECLARE
    owner_id uuid := gen_random_uuid();
    club_id uuid;
    target_session uuid;
    participant_ids uuid[] := ARRAY[]::uuid[];
    participant_count integer;
    court_count integer;
    round_count integer;
    player_number integer;
    seed_value integer;
    expected_matches integer;
    minimum_count integer;
    maximum_count integer;
    total_count integer;
    checked integer := 0;
    output jsonb;
    preview jsonb;
BEGIN
    INSERT INTO auth.users(id) VALUES (owner_id);
    PERFORM set_config('request.jwt.claim.sub',owner_id::text,true);
    SET LOCAL ROLE authenticated;
    output := public.league_command('create_club','{"name":"Schedule property fixtures"}'::jsonb,gen_random_uuid());
    club_id := (output->>'id')::uuid;
    FOR player_number IN 1..32 LOOP
        output := public.league_command('save_participant',jsonb_build_object('club_id',club_id,
            'display_name','Fixture '||player_number),gen_random_uuid());
        participant_ids := array_append(participant_ids,(output->>'participant_id')::uuid);
    END LOOP;
    FOREACH participant_count IN ARRAY ARRAY[4,5,6,8,10,16,32] LOOP
        FOREACH court_count IN ARRAY ARRAY[1,2,4] LOOP
            FOREACH round_count IN ARRAY ARRAY[1,3,12] LOOP
                output := public.league_command('create_session',jsonb_build_object('club_id',club_id,'title','Property fixture',
                    'starts_at',now()+interval '1 day','ends_at',now()+interval '26 hours','attendance_deadline',now()+interval '12 hours',
                    'location','Test court','capacity',32,'court_count',court_count,'round_count',round_count),gen_random_uuid());
                target_session := (output->>'id')::uuid;
                FOR player_number IN 1..participant_count LOOP
                    PERFORM public.league_command('respond_attendance',jsonb_build_object('session_id',target_session,
                        'club_participant_id',participant_ids[player_number],'response','attending'),gen_random_uuid());
                END LOOP;
                FOREACH seed_value IN ARRAY ARRAY[0,42] LOOP
                    preview := public.league_command('preview_schedule',jsonb_build_object('session_id',target_session,'seed',seed_value),gen_random_uuid());
                    expected_matches := least(court_count,participant_count/4)*round_count;
                    ASSERT jsonb_array_length(preview->'matches')=expected_matches,'match slot count mismatch';
                    SELECT min(played),max(played),sum(played) INTO minimum_count,maximum_count,total_count FROM (
                        SELECT COALESCE((preview->'appearances'->>participant.id::text)::int,0) AS played
                        FROM public.session_participants participant WHERE session_id=target_session) counts;
                    ASSERT total_count=expected_matches*4,'total appearances mismatch';
                    ASSERT maximum_count-minimum_count<=1,'appearance gap exceeded one';
                    ASSERT minimum_count=(expected_matches*4)/participant_count,'wrong minimum target';
                    ASSERT NOT EXISTS (
                        SELECT 1 FROM jsonb_array_elements(preview->'matches') match
                        CROSS JOIN LATERAL jsonb_array_elements_text((match->'team_a')||(match->'team_b')) player
                        GROUP BY match->>'round_index',player.value HAVING count(*)>1),'participant appears twice in a round';
                    ASSERT NOT EXISTS (
                        SELECT 1 FROM jsonb_array_elements(preview->'matches') match
                        GROUP BY match->>'round_index',match->>'court_id' HAVING count(*)>1),'court assigned twice in a round';
                    checked := checked+1;
                END LOOP;
            END LOOP;
        END LOOP;
    END LOOP;
    ASSERT checked=126,'unexpected property case count';
    SET LOCAL ROLE postgres;
    SET CONSTRAINTS ALL IMMEDIATE;
END;
$$;

SELECT '126 schedule property cases passed; fixtures rolled back' AS verification;
ROLLBACK;

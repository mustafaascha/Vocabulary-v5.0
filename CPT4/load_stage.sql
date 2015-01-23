-- 1. Update latest_update field to new date 
ALTER TABLE vocabulary ADD latest_update DATE;
UPDATE vocabulary SET latest_update=to_date('20141010','yyyymmdd') WHERE vocabulary_id='CPT4'; 
COMMIT;

-- 2. Truncate all working tables and remove indices
TRUNCATE TABLE concept_stage;
TRUNCATE TABLE concept_relationship_stage;
TRUNCATE TABLE concept_synonym_stage;
ALTER SESSION SET SKIP_UNUSABLE_INDEXES = TRUE; --disables error reporting of indexes and index partitions marked UNUSABLE
ALTER INDEX idx_cs_concept_code UNUSABLE;
ALTER INDEX idx_cs_concept_id UNUSABLE;
ALTER INDEX idx_concept_code_1 UNUSABLE;
ALTER INDEX idx_concept_code_2 UNUSABLE;

--3 Load concepts into concept_stage from MRCONSO
-- Main CPT codes. Str picked in certain order to get best concept_name
INSERT INTO concept_stage (concept_id,
                           concept_name,
                           domain_id,
                           vocabulary_id,
                           concept_class_id,
                           standard_concept,
                           concept_code,
                           valid_start_date,
                           valid_end_date,
                           invalid_reason)
   SELECT DISTINCT
          NULL AS concept_id,
          FIRST_VALUE (
             SUBSTR (str, 1, 255))
          OVER (
             PARTITION BY scui
             ORDER BY
                DECODE (tty,
                        'PT', 1,                             -- preferred term
                        'ETCLIN', 2,      -- Entry term, clinician description
                        'ETCF', 3, -- Entry term, consumer friendly description
                        'SY', 4,                                    -- Synonym
                        10))
             AS concept_name,
          NULL AS domain_id,                                -- adding manually
          'CPT4' AS vocabulary_id,
          'CPT4' AS concept_class_id,
          'S' AS standard_concept,
          scui AS concept_code,
          (SELECT latest_update
             FROM vocabulary
            WHERE vocabulary_id = 'CPT4')
             AS valid_start_date,
          TO_DATE ('20991231', 'yyyymmdd') AS valid_end_date,
          NULL AS invalid_reason
     FROM UMLS.mrconso
    WHERE     sab IN ('CPT', 'HCPT')
          AND suppress NOT IN ('E', 'O', 'Y')
          AND tty NOT IN ('HT', 'MP');
COMMIT;

-- CPT Modifiers
INSERT INTO concept_stage (concept_id,
                           concept_name,
                           domain_id,
                           vocabulary_id,
                           concept_class_id,
                           standard_concept,
                           concept_code,
                           valid_start_date,
                           valid_end_date,
                           invalid_reason)
   SELECT DISTINCT
          NULL AS concept_id,
          FIRST_VALUE (SUBSTR (str, 1, 255))
             OVER (PARTITION BY scui ORDER BY DECODE (sab, 'CPT', 1, 10))
             AS concept_name,
          NULL AS domain_id,
          'CPT4' AS vocabulary_id,
          'CPT4 Modifier' AS concept_class_id,
          'S' AS standard_concept,
          scui AS concept_code,
          (SELECT latest_update
             FROM vocabulary
            WHERE vocabulary_id = 'CPT4')
             AS valid_start_date,
          TO_DATE ('20991231', 'yyyymmdd') AS valid_end_date,
          NULL AS invalid_reason
     FROM UMLS.mrconso
    WHERE     sab IN ('CPT', 'HCPT')
          AND suppress NOT IN ('E', 'O', 'Y')
          AND tty = 'MP';
COMMIT;

-- Hierarchical CPT terms
INSERT INTO concept_stage (concept_id,
                           concept_name,
                           domain_id,
                           vocabulary_id,
                           concept_class_id,
                           standard_concept,
                           concept_code,
                           valid_start_date,
                           valid_end_date,
                           invalid_reason)
   SELECT DISTINCT NULL AS concept_id,
                   SUBSTR (str, 1, 255) AS concept_name,
                   NULL AS domain_id,
                   'CPT4' AS vocabulary_id,
                   'CPT4 Hierarchy' AS concept_class_id,
                   'C' AS standard_concept, -- not to appear in clinical tables, only for hierarchical search
                   scui AS concept_code,
                   (SELECT latest_update
                      FROM vocabulary
                     WHERE vocabulary_id = 'CPT4')
                      AS valid_start_date,
                   TO_DATE ('20991231', 'yyyymmdd') AS valid_end_date,
                   NULL AS invalid_reason
     FROM UMLS.mrconso
    WHERE     sab IN ('CPT', 'HCPT')
          AND suppress NOT IN ('E', 'O', 'Y')
          AND tty = 'HT';
COMMIT;

--4 Update domain_id in concept_stage from concept
UPDATE concept_stage cs
   SET (cs.domain_id) =
          (SELECT domain_id
             FROM concept c
            WHERE     c.concept_code = cs.concept_code
                  AND C.VOCABULARY_ID = CS.VOCABULARY_ID)
 WHERE cs.vocabulary_id = 'CPT4';
 COMMIT;
 
 --5 Pick up all different str values that are not obsolete or suppressed
INSERT INTO concept_synonym_stage (synonym_concept_id,
                                   synonym_concept_code,
                                   synonym_name,
                                   synonym_vocabulary_id,
                                   language_concept_id)
   SELECT DISTINCT NULL AS synonym_concept_id,
                   scui AS synonym_concept_code,
                   SUBSTR (str, 1, 1000) AS synonym_name,
				   'CPT4' as synonym_vocabulary_id,
                   4093769 AS language_concept_id
     FROM UMLS.mrconso
    WHERE sab IN ('CPT', 'HCPT') AND suppress NOT IN ('E', 'O', 'Y');
COMMIT;	

--6 Load concept_relationship_stage from the existing one. The reason is that there is no good source for these relationships, and we have to build the ones for new codes from UMLS and manually
INSERT INTO concept_relationship_stage (concept_id_1,
                                        concept_id_2,
                                        concept_code_1,
                                        concept_code_2,
                                        relationship_id,
                                        vocabulary_id_1,
                                        vocabulary_id_2,
                                        valid_start_date,
                                        valid_end_date,
                                        invalid_reason)
   SELECT NULL AS concept_id_1,
          NULL AS concept_id_2,
          c.concept_code AS concept_code_1,
          c1.concept_code AS concept_code_2,
          r.relationship_id AS relationship_id,
          c.vocabulary_id AS vocabulary_id_1,
          c1.vocabulary_id AS vocabulary_id_2,
          r.valid_start_date,
          r.valid_end_date,
          r.invalid_reason
     FROM concept_relationship r, concept c, concept c1
    WHERE     c.concept_id = r.concept_id_1
          AND c.vocabulary_id = 'CPT4'
          AND C1.CONCEPT_ID = r.concept_id_2; 
COMMIT;

--7 Create hierarchical relationships between HT and normal CPT codes
/*not done yet*/		  

--8 Extract all CPT4 codes inside the concept_name of other cpt codes. Currently, there are only 5 of them, with up to 4 codes in each
INSERT INTO concept_relationship_stage (concept_id_1,
                                        concept_id_2,
                                        concept_code_1,
                                        concept_code_2,
                                        relationship_id,
                                        vocabulary_id_1,
                                        vocabulary_id_2,
                                        valid_start_date,
                                        valid_end_date,
                                        invalid_reason)
   SELECT NULL AS concept_id_1,
          NULL AS concept_id_2,
          e.concept_code_1,
          e.concept_code_2,
          'Subsumes' AS relationship_id,
          'CPT4' AS vocabulary_id_1,
          'CPT4' AS vocabulary_id_2,
          TO_DATE ('19700101', 'yyyymmdd') AS valid_start_date,
          TO_DATE ('20991231', 'yyyymmdd') AS valid_end_date,
          NULL AS invalid_reason
     FROM (SELECT TRANSLATE (REGEXP_SUBSTR (concept_name,
                                            '\(\d\d\d\d[A-Z]\)',
                                            1,
                                            1),
                             '1()',
                             '1')
                     AS concept_code_1,
                  concept_code AS concept_code_2
             FROM concept_stage
            WHERE     vocabulary_id = 'CPT4'
                  AND REGEXP_INSTR (concept_name,
                                    '\(\d\d\d\d[A-Z]\)',
                                    1,
                                    1,
                                    0,
                                    'i') > 0
           UNION
           SELECT TRANSLATE (REGEXP_SUBSTR (concept_name,
                                            '\(\d\d\d\d[A-Z]\)',
                                            1,
                                            2),
                             '1()',
                             '1')
                     AS concept_code_1,
                  concept_code AS concept_code_2
             FROM concept_stage
            WHERE     vocabulary_id = 'CPT4'
                  AND REGEXP_INSTR (concept_name,
                                    '\(\d\d\d\d[A-Z]\)',
                                    1,
                                    1,
                                    0,
                                    'i') > 0
           UNION
           SELECT TRANSLATE (REGEXP_SUBSTR (concept_name,
                                            '\(\d\d\d\d[A-Z]\)',
                                            1,
                                            3),
                             '1()',
                             '1')
                     AS concept_code_1,
                  concept_code AS concept_code_2
             FROM concept_stage
            WHERE     vocabulary_id = 'CPT4'
                  AND REGEXP_INSTR (concept_name,
                                    '\(\d\d\d\d[A-Z]\)',
                                    1,
                                    1,
                                    0,
                                    'i') > 0
           UNION
           SELECT TRANSLATE (REGEXP_SUBSTR (concept_name,
                                            '\(\d\d\d\d[A-Z]\)',
                                            1,
                                            4),
                             '1()',
                             '1')
                     AS concept_code_1,
                  concept_code AS concept_code_2
             FROM concept_stage
            WHERE     vocabulary_id = 'CPT4'
                  AND REGEXP_INSTR (concept_name,
                                    '\(\d\d\d\d[A-Z]\)',
                                    1,
                                    1,
                                    0,
                                    'i') > 0
           UNION
           SELECT TRANSLATE (REGEXP_SUBSTR (concept_name,
                                            '\(\d\d\d\d[A-Z]\)',
                                            1,
                                            5),
                             '1()',
                             '1')
                     AS concept_code_1,
                  concept_code AS concept_code_2
             FROM concept_stage
            WHERE     vocabulary_id = 'CPT4'
                  AND REGEXP_INSTR (concept_name,
                                    '\(\d\d\d\d[A-Z]\)',
                                    1,
                                    1,
                                    0,
                                    'i') > 0) e
    WHERE e.concept_code_2 IS NOT NULL AND e.concept_code_1 IS NOT NULL;
COMMIT;	

--9 update dates from mrsat.atv (only for new concepts)
UPDATE concept_stage c1
   SET valid_start_date =
          (WITH t
                AS (SELECT DISTINCT TO_DATE (dt, 'yyyymmdd') dt, concept_code
                      FROM (SELECT TO_CHAR (s.atv) dt, c.concept_code
                              FROM concept_stage c
                                   LEFT JOIN UMLS.mrconso m
                                      ON     m.scui = c.concept_code
                                         AND m.sab in ('CPT', 'HCPT')
                                   LEFT JOIN UMLS.mrsat s
                                      ON s.cui = m.cui AND s.atn = 'DA'
                             WHERE     NOT EXISTS
                                          ( -- only new codes we don't already have
                                           SELECT 1
                                             FROM concept co
                                            WHERE     co.concept_code =
                                                         c.concept_code
                                                  AND co.vocabulary_id =
                                                         c.vocabulary_id)
                                   AND c.vocabulary_id = 'CPT4'
                                   AND c.concept_class_id = 'CPT4'
                           )
                     WHERE dt IS NOT NULL)
           SELECT COALESCE (dt, c1.valid_start_date)
             FROM t
            WHERE c1.concept_code = t.concept_code)
 WHERE     c1.vocabulary_id = 'CPT4'
       AND EXISTS
              (SELECT 1 concept_code
                 FROM (SELECT TO_CHAR (s.atv) dt, c.concept_code
                         FROM concept_stage c
                              LEFT JOIN UMLS.mrconso m
                                 ON m.scui = c.concept_code AND m.sab in ('CPT', 'HCPT')
                              LEFT JOIN UMLS.mrsat s
                                 ON s.cui = m.cui AND s.atn = 'DA'
                        WHERE     NOT EXISTS
                                     ( -- only new codes we don't already have
                                      SELECT 1
                                        FROM concept co
                                       WHERE     co.concept_code =
                                                    c.concept_code
                                             AND co.vocabulary_id =
                                                    c.vocabulary_id)
                              AND c.vocabulary_id = 'CPT4'
                              AND c.concept_class_id = 'CPT4') s
                WHERE dt IS NOT NULL AND s.concept_code = c1.concept_code);
COMMIT;				

--10 Create text for Medical Coder with new codes or codes missing the domain_id to add manually
--Then update domain_id in concept_stage from resulting file
	select * from concept_stage where domain_id is null and vocabulary_id='CPT4';

--11 Create text for Medical Coder with new codes and mappings
SELECT NULL AS concept_id_1,
       NULL AS concept_id_2,
       c.concept_code AS concept_code_1,
       u2.scui AS concept_code_2,
       'CPT4 - SNOMED eq' AS relationship_id, -- till here strawman for concept_relationship to be checked and filled out, the remaining are supportive information to be truncated in the return file
       c.concept_name AS cpt_name,
       u2.str AS snomed_str,
       sno.concept_id AS snomed_concept_id,
       sno.concept_name AS snomed_name
  FROM concept_stage c
       LEFT JOIN
       (                                          -- UMLS record for CPT4 code
        SELECT DISTINCT cui, scui
          FROM UMLS.mrconso
         WHERE sab IN ('CPT', 'HCPT') AND suppress NOT IN ('E', 'O', 'Y')) u1
          ON u1.scui = concept_code AND c.vocabulary_id = 'CPT4' -- join UMLS for code one
       LEFT JOIN
       (                        -- UMLS record for SNOMED code of the same cui
        SELECT DISTINCT
               cui,
               scui,
               FIRST_VALUE (
                  str)
               OVER (PARTITION BY scui
                     ORDER BY DECODE (tty,  'PT', 1,  'PTGB', 2,  10))
                  AS str
          FROM UMLS.mrconso
         WHERE sab IN ('SNOMEDCT_US') AND suppress NOT IN ('E', 'O', 'Y')) u2
          ON u2.cui = u1.cui
       LEFT JOIN concept sno
          ON sno.vocabulary_id = 'SNOMED' AND sno.concept_code = u2.scui -- SNOMED concept
 WHERE     NOT EXISTS
              (                        -- only new codes we don't already have
               SELECT 1
                 FROM concept co
                WHERE     co.concept_code = c.concept_code
                      AND co.vocabulary_id = 'CPT4')
       AND c.vocabulary_id = 'CPT4';
--12 Append resulting file from Medical Coder (in concept_relationship_stage format) to concept_relationship_stage

--13 Update concept_id in concept_stage from concept for existing concepts
UPDATE concept_stage cs
    SET cs.concept_id=(SELECT c.concept_id FROM concept c WHERE c.concept_code=cs.concept_code AND c.vocabulary_id=cs.vocabulary_id)
    WHERE cs.concept_id IS NULL
;
COMMIT;

--14 Reinstate constraints and indices
ALTER INDEX idx_cs_concept_code REBUILD NOLOGGING;
ALTER INDEX idx_cs_concept_id REBUILD NOLOGGING;
ALTER INDEX idx_concept_code_1 REBUILD NOLOGGING;
ALTER INDEX idx_concept_code_2 REBUILD NOLOGGING;	

-- At the end, the three tables concept_stage, concept_relationship_stage and concept_synonym_stage should be ready to be fed into the generic_update.sql script		
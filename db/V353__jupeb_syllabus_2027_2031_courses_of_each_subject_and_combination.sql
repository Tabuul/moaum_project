-- ═══════════════════════════════════════════════════════════════════════════
-- V353 — The JUPEB syllabus 2027–2031: each subject's courses, their semesters, objectives and topics, and the courses of
--         every subject combination
--
--   · The JUPEB Office gave the Board's syllabus for 2027–2031, extracted into a workbook (JUPEB_2027-2031_Extracted_Courses_
--     and_Syllabus.xlsx: Course Structure, Course Objectives, Syllabus Topics, Subject Objectives). Every sheet was checked
--     against the course structure — the same 77 courses, codes, titles and semesters on each. Nineteen of the Board's
--     subjects (J121 Christian Religious Studies … J155 Physics), each with two courses in the first semester and two in the
--     second (Mathematics: MAT 004A or MAT 004B in the second).
--   · The courses are the subject's course units, which the portal already keeps for the note on the statement of result
--     (V342: jupeb.subject_unit) — not a second list. A unit now carries its semester, credit units, the Board's subject it
--     belongs to, the syllabus's objectives and its topics (jupeb.unit_topic, in the order printed). Each of the Board's
--     subjects sits under the portal subject it is taught as (jupeb.board_subject): Economics is the Board's J133 with courses
--     ECN; Geography J134, GRY; History J123, HST; Mathematics J154, MAT; Visual Art J128, VSA. "Christian / Islamic Religious
--     Studies" is the Board's CRS or ISS, and "Igbo / Yoruba" IGB or YOR: the student takes one, and says which.
--   · Biology as the syllabus's Biology section has it, as the JUPEB Office decided: BIO 002 Botany (first semester), BIO 003
--     Microbiology (second). V342's sample statement had the two the other way round; they are corrected.
--   · The courses of a combination are the units of its three subjects: of an either/or subject, the option the student chose
--     (both until they choose); of Mathematics, MAT 004A Applied Mathematics for Science and Engineering combinations and MAT
--     004B Applied Business Mathematics for the others (the syllabus offers them as alternatives without saying who takes
--     which; the content decides it).
--   · The timetable names its courses as the syllabus does, as the JUPEB Office decided: ECO 001 is ECN 001 and GEO 001 GRY
--     001. A slot's course is one of its subject's units, taught in that semester (a subject with no units listed takes any
--     code), and the slot keeps the unit it is.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'jupeb', true),
       set_config('moaum.reason', 'V353: the JUPEB syllabus 2027-2031, its courses and the courses of each combination', true);

-- ── 1 · the syllabus and the Board's subjects ────────────────────────────────────────────────────────────────────
CREATE TABLE jupeb.syllabus (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code          text NOT NULL UNIQUE CHECK (code ~ '^[0-9]{4}-[0-9]{4}$'),
    title         text NOT NULL,
    source        text NULL,
    first_session text NOT NULL CHECK (first_session ~ '^[0-9]{4}/[0-9]{4}$'),
    last_session  text NOT NULL CHECK (last_session ~ '^[0-9]{4}/[0-9]{4}$'),
    loaded_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_jupeb_syllabus_span CHECK (last_session >= first_session)
);
SELECT audit.attach('jupeb.syllabus');
COMMENT ON TABLE jupeb.syllabus IS 'V353: an edition of the JUPEB Board''s syllabus and the sessions it is examined in (2027-2031: the sessions whose examinations fall in 2027 to 2031).';

INSERT INTO jupeb.syllabus (code, title, source, first_session, last_session)
VALUES ('2027-2031', 'JUPEB Syllabus 2027–2031', 'JUPEB SYLLABUS 2027-2031 (PDF), extracted to JUPEB_2027-2031_Extracted_Courses_and_Syllabus.xlsx', '2026/2027', '2030/2031');

CREATE TABLE jupeb.board_subject (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    syllabus_id uuid NOT NULL REFERENCES jupeb.syllabus(id),
    code        text NOT NULL CHECK (code ~ '^J[0-9]{3}$'),
    title       text NOT NULL CHECK (length(btrim(title)) BETWEEN 2 AND 160),
    prefix      text NOT NULL CHECK (prefix ~ '^[A-Z]{3}$'),
    subject_id  uuid NOT NULL REFERENCES jupeb.subject(id),
    objectives  text NULL,
    source_page int NULL,
    CONSTRAINT uq_jupeb_board_subject UNIQUE (syllabus_id, code),
    CONSTRAINT uq_jupeb_board_prefix UNIQUE (syllabus_id, prefix)
);
CREATE INDEX ix_jupeb_board_subject_subject ON jupeb.board_subject (subject_id);
SELECT audit.attach('jupeb.board_subject');
COMMENT ON TABLE jupeb.board_subject IS 'V353: a subject as the Board''s syllabus names it (J133 Economics, courses ECN), under the portal subject it is taught as; two under one portal subject (CRS and ISS, IGB and YOR) are options a student chooses between.';

-- ── 2 · the course units, as the syllabus has them, and their topics ──────────────────────────────────────────────
UPDATE jupeb.subject_unit SET code = regexp_replace(code, '^([A-Z]+) ?', '\1 ') WHERE code !~ '^[A-Z]+ ';
ALTER TABLE jupeb.subject_unit DROP CONSTRAINT subject_unit_code_check;
ALTER TABLE jupeb.subject_unit ADD CONSTRAINT ck_jupeb_unit_code CHECK (code ~ '^[A-Z]{2,5} [0-9]{3}[A-Z]?$');
ALTER TABLE jupeb.subject_unit ADD COLUMN semester int NULL CHECK (semester IN (1, 2));
ALTER TABLE jupeb.subject_unit ADD COLUMN credit_units int NULL CHECK (credit_units BETWEEN 1 AND 12);
ALTER TABLE jupeb.subject_unit ADD COLUMN board_subject_id uuid NULL REFERENCES jupeb.board_subject(id);
ALTER TABLE jupeb.subject_unit ADD COLUMN areas text[] NULL;
ALTER TABLE jupeb.subject_unit ADD COLUMN objectives text NULL;
ALTER TABLE jupeb.subject_unit ADD COLUMN source_page int NULL;
COMMENT ON COLUMN jupeb.subject_unit.areas IS 'V353: the combination areas that take this unit when it is one of alternatives (MAT 004A: Science, Engineering; MAT 004B: the others); empty, every combination with the subject.';

CREATE TABLE jupeb.unit_topic (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    unit_id     uuid NOT NULL REFERENCES jupeb.subject_unit(id),
    ord         int NOT NULL CHECK (ord > 0),
    sn          text NULL,
    topic       text NULL,
    sub_topic   text NULL,
    details     text NULL,
    source_page int NULL,
    CONSTRAINT uq_jupeb_unit_topic UNIQUE (unit_id, ord)
);
SELECT audit.attach('jupeb.unit_topic');
COMMENT ON TABLE jupeb.unit_topic IS 'V353: a row of a course unit''s syllabus table, in the order printed: S/N, topic, sub-topic, details and notes; a blank S/N or topic continues the one above.';

-- ── 3 · the syllabus 2027–2031, from the workbook ──────────────────────────────────────────────────────────────
-- the Board's subjects of the 2027–2031 syllabus, each under the portal subject it is taught as
INSERT INTO jupeb.board_subject (syllabus_id, code, title, prefix, subject_id, objectives, source_page)
SELECT (SELECT id FROM jupeb.syllabus WHERE code = '2027-2031'), v.code, v.title, v.prefix, s.id, v.objectives, v.page FROM (VALUES
    ('J121', 'Christian Religious Studies', 'CRS', 'CRS/ISS', 'At the end of the course, candidates should be able to:
1. explain how the Old and New Testaments came into existence;
2. identify the outstanding kings and prophets of Israel during the monarchy and outline their contributions to the religious, social, and political development of Israel;
3. trace the history and development of Christianity in West Africa, with particular reference to Sierra Leone and Nigeria;
4. discuss the relationship between religion and society, with emphasis on human values such as dignity, security, power, and prestige, in the context of basic rights, duties, and religious sanctions; and
5. highlight the Christian response to specific contemporary societal challenges, analyse their effects on individuals and society, and propose appropriate solutions. 11', 12::int),
    ('J122', 'French', 'FRE', 'FRE', NULL, 30::int),
    ('J123', 'History', 'HST', 'HIS', 'At the end of course, candidates should be able to:
1. discuss and appreciate the nature and essence of History as a discipline;
2. examine the dynamics that have shaped human history across the centuries since the onset of civilization;
3. demonstrate an understanding of the social, economic, cultural, and political factors that have influenced societies and peoples in Africa;
4. trace and explain the chronological sequence of major processes of historical change; and
5. describe and analyze the forces that have driven significant transformations in human societies across time and space.', 47::int),
    ('J124', 'Igbo', 'IGB', 'IGB/YOR', 'At the end of the course of study, the candidates should be able to:
1. expose students to various aspects of the Igbo language, linguistics, literature, and culture with a view to helping them achieve greater competence and sophistication in their understanding and appreciation of the values inherent in those aspects;
2. train them to be able to apply their knowledge for the advancement of their society;
3. prepare them for further studies in the discipline and/or for relevant careers (e.g., teaching, administration, etc.);
4. explore language use by sub-Saharan Africans to understand, organize, and transmit indigenous knowledge to successive generations. Language serves as a road map to understanding how social, political, and economic institutions and processes develop from kinship structures, the evolution of political offices, trade relations, to the transfer of environmental knowledge;
5. expose students to the study of an African language at the elementary, intermediate, and advanced levels through contact hours with a language coach, etc., and
6. equip the students with creative skills required for self-development and entrepreneurship.
7. train students on the dynamics of deploying technological tools such as infotech and Artificial Intelligence (AI) in creating and analysing of language and literature texts for the purpose of keeping abreast of developments in a globalised world.', 70::int),
    ('J125', 'Islamic Studies', 'ISS', 'CRS/ISS', 'At the end of this course, candidates should be able to:
1. discuss the fundamental principles of Islam and the primary sources of its tenets;
2. evaluate the history of Islam with reference to the significance of key events in the life of Prophet Muhammad (PBUH) and the achievements of the Khulafā’ ar-Rāshidūn;
3. appraise the major features of the Qur’ān and its emergence as a divine scripture;
4. analyse the social, moral, political, and economic dimensions of Islamic forms of worship;
5. discuss the basic methodologies involved in Hadīth studies and the significance of Hadīth literature in Islam; and
6. enhance learners’ capacity to engage with Islam as a dynamic culture and civilization, appreciating its historical development and contemporary relevance.', 86::int),
    ('J126', 'Literature-in-English', 'LIT', 'LIT', 'At the end of the programme, the candidate should be able to:
1. identify the features of Literature and understand a variety of literary-critical terms and concepts;
2. develop an awareness of the relationship between content and literary form;
3. demonstrate the relevance of Drama, Prose Fiction and Poetry to the individual and society;
4. acquire skills and confidence in reading, speaking, and writing about literature;
5. gain knowledge of the major traditions of literatures, and develop an appreciation for the diversity of literary and social norms within each tradition;
6. apply the acquired skills and knowledge in active reading or close analysis of texts;
7. cultivate the capacity to judge the aesthetic, ethical and cultural values of literary texts as well as articulate the standards behind their judgments;
8. cultivate the ability for informed personal response to texts across different genres, cultures and traditions;
9. develop the critical skills necessary for advanced undergraduate work in literature;
10. inculcate the culture of extensive reading as precursor to personal development.', 101::int),
    ('J127', 'Music', 'MUS', 'MUS', 'At the end of this course, candidates should be able to:
1. identify and conceptualize key elements of music theory;
2. analyse and evaluate African music as well as the music of other world cultures;
3. play the pianoforte and/or other selected instruments to a competent level;
4. describe chronological trends in Western and African music history;
5. demonstrate basic techniques for performing Western and African musical pieces on various instruments;
6. carry out technical exercises, including scales and arpeggios, and demonstrate proficiency on selected/available African musical instruments; and
7. perform selected Western and African musical compositions accurately and expressively (maybe up to grade three level).', 113::int),
    ('J128', 'Visual Arts', 'VSA', 'VAR', 'At the end of this course, the candidates should be able to:
1. demonstrate the ability to work from direct observation and personal experience;
2. apply creative and critical thinking in solving visual art problems;
3. display confidence and competence in visual problem-solving showing knowledge of the formal properties in a work of art;
4. develop enduring technical skills relevant to visual arts
5. demonstrating 21st century skill-set in digital art production and practice;
6. demonstrate knowledge of the historical and theoretical foundations of major art forms, while exhibiting a sense of aesthetic expression in relation to art appreciation;
7. handle two- and three-dimensional art projects with confidence and creativity;
8. produce finished works in both two- and three-dimensional media;
9. identify and select a potential area of specialization for further study in visual arts; and
10. develop entrepreneurial skills for self-reliance and professional practice in the visual arts.', 127::int),
    ('J129', 'Yorùbá', 'YOR', 'IGB/YOR', 'At the end of this of course, candidates should be able to:
1. assess various aspects of Yorùbá language, linguistics, literature and culture.
2. appreciate how language serves as a road map to the understanding of social, political, and economic institutions and processes in order to strengthen kinship structures, social and moral values.
3. classify Yorùbá speech sounds into their natural classes using phonetic features and discuss the phonological processes that such speech sounds may undergo in utterance;
4. itemize and describe the Yorùbá lexical categories and their syntactic distributions;
5. define, classify and discuss the features of oral literature (drama, poetry, and prose); and demonstrate their relevance to the individual and society at large;
6. define, classify and discuss the features, of written Yorùbá literature (drama, poetry, and prose) and, demonstrate their relevance to the individual and society at large.', 137::int),
    ('J131', 'Accounting', 'ACC', 'ACC', 'The candidates writing Accounting paper should be able to:
1. explain the nature, scope of Financial Accounting, basic accounting processes and regulatory framework.
2. Correct accounting errors and reconcile the Cash Book balance with the Bank Statement balance;
3. prepare Financial Statements of Sole Proprietorships, Partnerships, Not-for- Profit Organisations, and Limited Liability Companies for internal use, considering end-of-period adjustments;
4. explain the concepts and principles of cost and management accounting;
5. analyze and predict cost as output and market conditions change, and determine its impact on profit;
6. apply the principle of double entry to cost accounting
7. demonstrate an understanding of the history, nature, concepts and principles of auditing;
8. explain the concepts of audit framework and audit communication
9. prepare audit report
10. discuss the nature, structure, and functions of the Nigerian tax administration; and
11. compute taxes payable by applying the prevailing corporate tax rates.', 149::int),
    ('J132', 'Business Studies', 'BUS', 'BUS', 'At the end of the series of courses, candidates should be able to:
1. discuss and appreciate the nature and scope of business as well as its role within a business environment.
2. develop a critical understanding of organizations and the markets they serve.
3. analyze the role of business from the perspective of various stakeholders such as customers, managers, creditors, owners/shareholders, and employees.
4. discuss issues related to budgeting, financial management, and financial performance.
5. examine the economic, environmental, ethical, governmental, legal, social, and technological issues associated with business activities; and
6. develop essential skills in decision-making, problem-solving, information management, and effective communication.', 169::int),
    ('J133', 'Economics', 'ECN', 'ECO', 'At the end of the course of study, candidates should be able to:
1. explain basic economic concepts relevant to solving individual, organizational and societal problems;
2. apply fundamental economic tools and methods of analysis to enhance economic reasoning and decision-making;
3. describe the relationships among basic economic units in terms of factor and income flows within and outside the economic system;
4. develop the ability to apply analytical tools, knowledge, and skills to address economic challenges in society;
5. appreciate the methods employed by economists and the effective ways of analyzing, correlating, discussing, and presenting economic data; and
6. understand and apply relevant economic theories to the analysis and solutions of real-world economic problems.', 181::int),
    ('J134', 'Geography', 'GRY', 'GEO', 'At the end of the series of courses, candidates should be able to:
1. acquire a broad and well-balanced knowledge of geographical concepts, theories, and methods;
2. explain the elements, processes, and factors that shape global, national, and local environments, as well as the interactions between humans and their environments;
3. discuss the areal differentiation and linkages that characterize various environments;
4. demonstrate a sound knowledge of Geography, appreciate its applications in different socio-cultural contexts, and engage in an intellectually stimulating and rewarding study of the workings of society;
5. apply geographical knowledge and skills to analyze spatial pattern and attributes, and propose solutions to contemporary and emerging societal problems both natural and human-induced in Nigeria and beyond;
6. possess the relevant knowledge and competencies required to pursue further studies in specialized or multidisciplinary fields related to Geography;
7. recognize diverse career opportunities in areas such as Geographic Information Systems (GIS), cartography, urban and regional planning, environmental management, climate change mitigation, and related fields;
8. appreciate spatial thinking, cultural diversity, and the relevance of Geography in socio-cultural, economic, and environmental contexts at local, national, and global scales; and
9. develop transferable skills and competencies including research, communication, entrepreneurship, and digital literacy necessary for employment, lifelong learning, and self-reliance in a rapidly changing world.', 204::int),
    ('J135', 'Government', 'GOV', 'GOV', 'At the end of the series of courses, candidates should be able to:
1. describe the basic concepts, principles, institutions, and issues in government, politics, political economy, public administration, and international relations;
2. explain the structures, institutions, and processes of government;
3. discuss the historical, political, and constitutional development of Nigeria from the pre-colonial era to the present;
4. examine critical issues in African government and politics;
5. evaluate the political systems of selected African states.', 226::int),
    ('J151', 'Agricultural Science', 'AGR', 'AGR', 'At the end of the series of courses, candidates should be able to:
1. enumerate the principles of agriculture;
2. explain how agricultural knowledge can be applied to identify and solve agricultural problems;
3. demonstrate effective agricultural practices and techniques;
4. list and describe positive attitudes and practices required for the conservation of natural resources and their sustainable use;
5. acquire a solid foundation for the study of agriculture and related disciplines at the tertiary level, as well as for professional programmes requiring agricultural knowledge such as bee-keeping ,fishery, epiculture, mushroom production among others;
6. describe the structural changes that occur after fertilization leading to the development of seeds and fruits;
7. discuss the factors affecting water and nutrient uptake in plants and explain the mechanisms of water uptake (osmosis) and nutrient uptake (active transport);
8. explain plant anatomy and the factors influencing photosynthesis, including the carbon dioxide compensation point (C₃ and C₄ systems);
9. identify, classify and control of common farm weeds,
10. identify farm equipment and machineries; explain the operational principles, uses, and maintenance of farm equipment and machineries such as tractors, harrows, ploughs, ridgers, and sprayers;
11. explain horticulture, different types of it and discuss the importance of horticulture in Nigeria; and
12. explain the principles of Agricultural Extension, define and state the importance of agricultural accounting and finance.', 246::int),
    ('J152', 'Biology', 'BIO', 'BIO', NULL, 261::int),
    ('J153', 'Chemistry', 'CHM', 'CHM', 'At the end of the series of courses, candidates should be able to:
1. receive systematic instruction and access appropriate facilities for the acquisition of knowledge in the field of Chemistry;
2. build upon the knowledge and skills acquired in Chemistry at the Senior Secondary School level;
3. acquire advanced understanding of chemical concepts and principles through well-selected content;
4. develop and improve laboratory skills, including an awareness of hazards and adherence to safety procedures;
5. gain adequate academic and technical knowledge relevant to professional careers in industries, government agencies, research institutes, and academia;
6. develop a sustained interest in Chemistry and derive enjoyment and satisfaction from its study;
7. deduce the electronic configurations of atoms and ions from their proton numbers.
8. explain qualitatively the periodic variations in atomic properties;
9. describe different types of chemical bonding (ionic, covalent, coordinate, metallic, etc.);
10. predict molecular shapes and bond angles using the Valence Shell Electron Pair Repulsion (VSEPR) theory;
11. describe intermolecular forces and relate them to the observed properties of compounds;
12. perform stoichiometric calculations accurately; and
13. distinguish between different types of chemical reactions.', 281::int),
    ('J154', 'Mathematics', 'MAT', 'MTH', 'The general objectives of this course are to:
1. develop logical thinking, abstract reasoning, and precision in mathematical problem solving;
2. sharpens students’ ability to apply mathematical skills to solve real-life problems in business, engineering, and sciences;
3. equip students to solve mathematical problems creatively, and communicate their solutions effectively; and
4. establish a solid foundation in Mathematics to support students’ future academic and professional endeavours.', 300::int),
    ('J155', 'Physics', 'PHY', 'PHY', 'At the end of the courses in this syllabus, candidates should be able to:
1. describe various physical phenomena at both microscopic and macroscopic levels;
2. analyse and apply the laws and principles of Physics to solve real-life problems;
3. design and conduct experiments, implement procedures effectively, and draw meaningful inferences from results;
4. explain natural and physical phenomena using established laws and concepts of Physics;
5. develop and apply creativity in addressing everyday challenges through scientific reasoning;
6. prepare for further and higher studies in Physics and related disciplines; and
7. acquire adequate knowledge of Physics to adapt to and contribute to modern technological advancements.', 313::int)
  ) AS v(code, title, prefix, portal, objectives, page) JOIN jupeb.subject s ON s.code = v.portal
ON CONFLICT (syllabus_id, code) DO UPDATE SET title = EXCLUDED.title, prefix = EXCLUDED.prefix, subject_id = EXCLUDED.subject_id, objectives = EXCLUDED.objectives, source_page = EXCLUDED.source_page;

-- the course units: the syllabus's titles, semesters, credit units and objectives (BIO 002 Botany and BIO 003 Microbiology, as its Biology section has them)
INSERT INTO jupeb.subject_unit (subject_id, code, title, ord, semester, credit_units, board_subject_id, areas, objectives, source_page)
SELECT b.subject_id, v.code, v.title, v.ord, v.semester, v.credit, b.id, v.areas, v.objectives, v.page FROM (VALUES
    ('J121', 'CRS 001', 'Old Testament Studies: History and Religion of Israel', 1, 1, 3, NULL::text[], 'At the end of the study of this course, candidates should be able to:
1. explain the concept of inspiration and analyse the process of canonization of the Old Testament;
2. highlight various categories of the Canonical Books;
3. identify the Hebrew words, grammar, and syntax;
4. identify the various genres of Old Testament literature and discuss the issues surrounding the Documentary Hypothesis;
5. evaluate the origins of the nation of Israel, examine the factors that led to the establishment of the monarchy, and describe the roles of notable kings like Saul, David, and Solomon in the religious and socio-political development of the land; and
6. appraise prophecy in Israel and assess the influence of prophets such as Isaiah, Hosea, and Amos. 12', 12::int),
    ('J121', 'CRS 002', 'New Testament Studies: The Gospels, Pauline and Pastoral Epistles', 2, 1, 3, NULL::text[], 'At the end of this course, candidates should be able to:
1. provide a synopsis of New Testament literature and highlight its background, including an overview of the socio-political and religious institutions such as the Maccabees, Sanhedrin, Pharisees, and the Temple;
2. clarify the term Synoptic, explain why the first three Gospels are so called, examine the Synoptic Problem, and propose possible solutions;
3. present a comprehensive exposition of the modern criticism of the Synoptic Gospels and identify the aims and approaches of the critics;
4. provide evidence of Paul’s writings before the Gospels were written. Paul’s conversation and the main contents of his letters; and
5. know the contents of the Epistles - their universality and general outlook.', 17::int),
    ('J121', 'CRS 003', 'History of Christianity in West Africa', 3, 2, 3, NULL::text[], 'At the end of the course, candidates should be able to:
1. provide an overview of earlier attempts at Christianizing Africa, including the spread of Christianity in North Africa and the efforts of the Portuguese in West Africa;
2. describe the establishment of Christianity in Sierra Leone, with emphasis on the roles of the Abolitionists, notable individuals, and the ex-slaves;
3. discuss the introduction of Christianity to Nigeria;
4. highlight the influence of Christianity in various parts of Nigeria and discuss the rise, characteristics, and expansion of the African Independent Churches;
5. examine Pentecostalism and the emergence of new religious movements within the Church in Nigeria, providing a critical assessment of the causes and impacts of church proliferation in the country; and
6. study the rise, growth and impact of various Christian associations in Nigeria 19', 19::int),
    ('J121', 'CRS 004', 'Religion and Society', 4, 2, 3, NULL::text[], 'At the end of this course, candidates should be able to:
1. clarify the concepts of religion and society and discuss the relationship between them;
2. identify and critically appraise the various theories of religion;
3. discuss the methods and challenges involved in measuring religiosity;
4. explain the role and significance of religion in society; and
5. examine the appropriate Christian response to contemporary societal issues. 23', 23::int),
    ('J122', 'FRE 001', 'Oral & Basic French I (Phonetics & Grammar)', 1, 1, 3, NULL::text[], 'At the end of this course, candidates should be able to:
1. pronounce French words correctly; and
2. express themselves freely and participate effectively in meaningful discussions. 30', 30::int),
    ('J122', 'FRE 002', 'Basic Writing, Literature & Civilisation I', 2, 1, 3, NULL::text[], ':
At the end of this course, candidates should be able to:
1. write both short and extended sentences correctly in French language; and
2. speak confidently about aspects of literature, civilization and culture.', 36::int),
    ('J122', 'FRE 003', 'Oral & Basic French II (Phonetics & Grammar)', 3, 2, 3, NULL::text[], 'This course is designed to enable candidates to comprehend and accurately report information obtained from print media, radio, and television broadcasts in the French language. It will also assist the candidates to bridge the gap between English and French via simple translation. 39', 39::int),
    ('J122', 'FRE 004', 'Basic Writing, Literature & Civilisation II', 4, 2, 3, NULL::text[], 'This course is designed to enable candidates to write more elaborate texts in French, including formal and informal letters, descriptive, narrative, and argumentative essays.', 42::int),
    ('J123', 'HST 001', 'African History I', 1, 1, 3, NULL::text[], 'At the end of the course, the candidates should be able to:
1. explain the meaning, sources, approaches and importance of History;
2. describe the factors responsible for the emergence, growth, and development of ancient empires in the West Africa such as Ghana, and Mali;
3. explain the factors that led to the decline and fall of these ancient empires;
4. examine Trans-Saharan trade, Intergroup Relations, Islam and introduction of Christianity before 1500. 47', 47::int),
    ('J123', 'HST 002', 'World History I', 2, 1, 3, NULL::text[], 'At the end of the course, candidates should be able to:
i. explain human evolution and major world civilizations ii. analyze major themes in economic history iii. examine the voyages of exploration and Africans dispersal and their impact in the world. 55', 55::int),
    ('J123', 'HST 003', 'African History II', 3, 2, 3, NULL::text[], 'At the end of the course, candidates are expected to
1. describe the emergence, spread, and impact of colonialism on the African continent; and 2. 3. 4.
5. evaluate the various systems of colonial administration practiced in Africa. 61', 61::int),
    ('J123', 'HST 004', 'World History II', 4, 2, 3, NULL::text[], 'At the end of the course, candidates should be able to narrate the transformation from manual to mechanized systems of production and explain how the collapse of ancient regimes in Europe gave rise to a new international world order.', 63::int),
    ('J124', 'IGB 001', 'Fundamentals of Igbo Phonology', 1, 1, 3, NULL::text[], 'At the end of the course, students should be able to:
i. train students to have adequate knowledge of the history of Igbo orthography; ii. give students a strong background to the fundamental aspects of Igbo speech sounds; iii. train students to be able to identify, describe and analyse the syllable in Igbo language; iv. expose students to the knowledge of phonological processes in Igbo and the ability to analyse them; and v. give students adequate training on the dynamics of Igbo tone system', 70::int),
    ('J124', 'IGB 002', 'Fundamentals of Oral Igbo Literature', 2, 1, 3, NULL::text[], 'At the end of this course, candidates should be able to:
i. demonstrate and help students understand the three major genres of oral Igbo Literature; ii. describe to students the nature, scope and significance of oral literature; iii. To help students understand identify the various sub-genres of oral Igbo Literature; iv. To explain the basic features and rudiments of oral literature sub-genres in oral Igbo literature; and 72 v. To train students on the use of oral forms generated and moderated by AI and acquaint students with AI generated chants in relation with oral Igbo literature.', 72::int),
    ('J124', 'IGB 003', 'Fundamentals of Igbo Grammar', 3, 2, 3, NULL::text[], 'At the end of this course, candidates should be able to:
74 i. grant students the knowledge to identify word classes in the Igbo language and describe their key characteristics; ii. enable students to identify and categorise various types of phrases in Igbo; iii. expose students to the typology of sentences in Igbo; iv. equip students with the skills necessary to compose texts of various kinds as well as text appreciation in Igbo; v. expose students to the concept of morphology and word formation processes in Igbo; vi. introduce students to the concept of linguistics as the science of language and its various components; vii. expose students to the branch of linguistics where theoretical knowledge is applied to solve human problems in society; and viii. equip students with the requisite skills they need to translate documents from Igbo to another language or from another language to Igbo.', 74::int),
    ('J124', 'IGB 004', 'Fundamentals of Written Igbo Literature', 4, 2, 3, NULL::text[], 'At the end of this course, candidates should be able to:
i. expose students to have the knowledge of the development and growth of written Igbo Literature, including Igbo poetry, novel, and drama; ii. acquaint students with the knowledge of written Igbo literature, Types of written Igbo literature, Features of written Igbo literature, and genres of written Igbo literature; iii. equip students with the knowledge of differentiate between oral and written forms of Igbo literature and to have skills of analysing Igbo Literary texts on the basis of their theme, setting, character, plot, point of view, style/language, and tone of voice; 77 iv. imbibe in students adequate knowledge of the transition of Igbo literature from the oral tradition to written form; and v. equip students with the basic knowledge required to understand and analyze Igbo poetry, novel, and drama. It will also help the students understand how to use Artificial Intelligence (AI) as a tool in creative writing of Igbo Literature. COURSE CONTENT S/N TOPICS SUB-TOPIC DETAILS AND NOTES
1. The development and i. Igbo Word A preliminary study of the growth of written Igbo Compilation and development, growth, Literature Documentation Written Igbo Literature, Period (1766 – 1857) and genres of Written ii. Igbo literature Igbo Literature: poetry, Translated from prose and drama foreign literatures exemplified by selected (1857-1932) works
2. Written Igbo literature i. Definition of Written a. Written Igbo Igbo Literature Literature ii. Importance of – The novel (early Written Igbo Igbo novel 1933 – Literature 1970) iii. Features of Written Igbo Literature b. Written Igbo poetry iv. Types of Igbo
– A survey of Literature (Oral and written Igbo poetry Written) v. Differences between c. Written Igbo Drama Oral and Written Igbo Literature vi. The Genres of Written Igbo Literature a. Abụ Ederede (Written Poetry 78 b. Iduuazị/Akọmakọ Ederede (Novel/Written Igbo Prose Narrative) c. Ejije Ederede (Written Drama) vii. Artificial Intelligence as a tool in creative writing of Igbo Literature. viii. Sources of events in Igbo literary works ix. The Basis for Analyzing Igbo Literature a. Theme b. Setting c. Character d. Plot e. Point of view f. Style/Language g. Tone of voice
3. Written Igbo Poetry i. A Survey of Written Igbo Poetry (1975 – Date) i. Definition of Written Igbo Poetry ii. Features of Written Igbo Poetry iii. Types of Written Igbo Poetry iv. Analysis of Written Igbo Poetry a. Content:
Topic/Sub-Topic b. Form: Structure, Rthym, and Language 79
4. Written Igbo Novel i. The Emergence of Igbo Novel (1933 -1970) ii. The Transitional Gap Period/War Period (1967 – 1972) iii. The Revival of Written Igbo Novel/Written Igbo Prose Narrative (1973
– Date) iv. Definition of Igbo Novel v. Features of Igbo Novel vi. Types of Novels vii. Analysis of Igbo Novel a. Content:
Topic/Sub-Topic b. Form: Narrative device, Agwa, and Language
5. Written Igbo Drama v. Written Igbo Drama (1974 – Date) vi. Definition of Writen Igbo Drama vii. Features of Written Igbo Drama viii. Types of Written Igbo Drama ix. Analysis of Written Igbo Drama c. Content:
Topic/Sub-Topic d. Form: Dramatic Convention, Structure, Character, and Language 80 RECOMMENDED TEXTS General Books For Language:
1. Mbah, B.M., E.E. Mbah, E.S. Ikeokwu et al. (2013).Ìgbò Àdị Igbo-English English-Ibo Dictionary of Linguistics and Literary Terms Nsukka: University of Nigeria Press.
2. Mbah, B.M. (ed.) (2016). Theories of Linguistics. Nsukka: University of Nigeria Press. Phonology
1. Ezikeojiakụ, P.A. (1989). Fọnọlọji Na Ụtọasụsụ Igbo. Ilupeju: Macmillan Nigeria Publishers.
2. Nwaeke, P.C.O. (2009). The Simplified Igbo Language Text for Schools and Colleges. Green Olive.
3. Mgbemena, U-A. (2011). Orthography: The Igbo Example. Lagos: Sam Iroanusi Publications.
4. Ugwuona, C.N., O.A. Nwankwo & M.I. Nweze (2020). Ntọala na Isiokwu Ụfọdụ na Fọnọlọji Igbo Tinyere Olundị. Nsukka: University of Nigeria Press. Syntax
1. Anedo, O.A (2014). Ndehie n’ide Asusu Igbo Na Ufodu Ihe Omumu Utoasusu Igbo. Awka:
2. Anọzie, C.C. (1999). Lingwistiiki (Sayensi Asụsụ). Enugu: Computer Edge Publishers. Besing Books.
3. Asoonye, U-M. (2011). Orthography: The Igbo Example. Lagos: Sam Iroanusi Publications.
4. Emenanjo, E.N. (2015). A grammar of Contemporary Igbo. Port-Harcourt: M & J Grand Orbit Communications LTD.
5. Holmes, J. (2008). Introduction to Sociolinguistics (3rd Edition). London:
Routledge 81
6. Nwaeke, P.C.O. (2009). The Simplified Igbo Language Text for Schools and Colleges. Green Olive.
7. Uba-Mgbemena, A. (2006). Ntọala Usoroasụsụ Igbo. Ibadan: Gold Press. General Books For Literature
1. Uzoma. (Nwadike, I. U. (1992). Ntọala Agụmagụ Igbo. Ihiala: Deo Gratia.
2. Nwadike, I. U. (2008). Igbo Studies: From the Plantation of West Indies to the Forestlands of West Africa, 1766-2008. University of Nigeria, Nsukka:
University of Nigeria Press.
3. Nwadike, I.U. (1992). Ntọala Agụmagụ Igbo. Ihiala: Deo Gratia.
4. Emenanjo, E.N. (1989). Atụmatụ Okwu na Atụmatụ Agụmagụ. Ikeja: Longman Nigeria Publishers.
5. Emenanjo, E.N. (1998). Ụkabụilu Ndị Igbo. Aba: NINLAN Press.
6. Uzochukwu, S. (2009). Akanka na Nnyocha Agumagu Igbo (Igbo Stylistics and Literary Criticism). Lagos: Green Olive.
7. Nwadike, I. U. (2009). Igbo Proverb (A Wider Perspectives). Enugu: Paschal Communications. Oral Igbo Literature
1. Ekechukwu, R.M. (ed.), (1975). Akpa Uche Ibadan: O.U.P.
2. Maduekwe, J.C. (1979). Nka Okwu. Ikeja: Longman Nigeria Publishers.
3. Nwizu, P. C., Obiakor, E. E., Egonu, N. G., Chibundu, V. C. and Onwujialiri, O. I. (2021). Omanala Igbo Ga-adi. Owerri : Hysab Prints and Publishers.
4. Okemlama, C. N. (2003). Mkpolite Agumagu Onu Igbo. Enugu: Snaap Press.
5. Ugonna, N. (1980). Abu na Egwuregwu Odinala Igbo. Ikeja: Longman Publishers. Written Igbo Literature Drama
1. Chukuezi, A.B. (1974). Udo Ka Mma. Ibadan: O.U.P. 82
2. Ọdụnke Artists (1977). Ọjaadịlị. Ibadan: O.U.P
3. Nwaozuzu, G. I. (2013). Nke M Ji Ka. (Ejiji Igbo). Enugu: Format Publishers.
4. Anedo, O. A. (2024). Ekwutosi. Ifite-Awka: Raphtex Press.
5. Nwadike, I. U. (1991). Okwe Agbaala. Lagos: Macmillan Nigeria Publishers. Prose
1. Nwana, P. (1933). Omenụkọ London: Longman & Green.
2. Achara, D.N. (1933). Ala Bingo. London: Longman & Green.
3. Egonu, N. G. (2021). Mpụ Na Arụrụala N’Ụlọakwụkwọ Alaike. Owerre, Imo State: Trumpeters Concept.
4. Anedo, O. A. (2025). Agwo Na Ihe O Loro. Nnamdi Azikiwe University, Awka, Anambra: Raphtex Press.
5. Anedo, O. A. A. (2025). Ọkụkọ Nyụọ Ahụrụ. Nnamdi Azikiwe University, Anambra State: Raphtex Press.
6. Okafor-Maduka, C. N. (2026). Chimdindu. Onitsha: Openpage Publishers. Poetry
1. Uzochukwu, S. (1985). Mbem Akwamozu. Onitsha: University Publishing Company.
2. Ekechukwu, R.M. (ed.), (1975). Akpa Uche Ibadan: O.U.P.
3. Maduekwe, J.C. (1979). Nka Okwu. Ikeja: Longman Nigeria Publishers.
4. Emenajo, N. (1981). Utara Nti (Anthology of Igbo poetry and verse). Ibadan:
Evans Brothers.
5. Ifeka, O. R. (Ed.) (2014). Ibeene, (Anthology of Igbo Contemporary Poetry). Onitsha: Africana First Publishers.
6. Okafor-Maduka, C. N. (2026). Abu Ohuu Igbo. Nkpor/Onitsha: Perfect Image Publishers
7. Uba-Mgbemena, A. (2012). Echiche. Ibadan: Gold Press.
8. Anozie, C. C. (2007). Uche bụ Akpa. Onitsha: Varsity Press. 83 SYLLABUS FOR ARTS - J125 ISLAMIC STUDIES 84 SYLLABUS FOR ARTS - J125 ISLAMIC STUDIES GENERAL OBJECTIVES At the end of this course, candidates should be able to:
1. discuss the fundamental principles of Islam and the primary sources of its tenets;
2. evaluate the history of Islam with reference to the significance of key events in the life of Prophet Muhammad (PBUH) and the achievements of the Khulafā’ ar-Rāshidūn;
3. appraise the major features of the Qur’ān and its emergence as a divine scripture;
4. analyse the social, moral, political, and economic dimensions of Islamic forms of worship;
5. discuss the basic methodologies involved in Hadīth studies and the significance of Hadīth literature in Islam; and
6. enhance learners’ capacity to engage with Islam as a dynamic culture and civilization, appreciating its historical development and contemporary relevance. FIRST SEMESTER ISS 001: HISTORY OF ISLAM (3 Units) ISS 002: TAWHĪD AND IBĀDĀT (3 Units) 85 SECOND SEMESTER ISS 003: QUR’ĀNIC STUDIES (3 units) ISS 004: INTRODUCTION TO THE STUDY OF HADĪTH (3 Units) COURSE DESCRIPTION ISS 001: History of Islam Specific Objectives At the end of this course, candidates should be able to:
1. classify the history of Islam into distinct periods and examine the defining features of each;
2. justify the relevance of the biography of Prophet Muhammad (PBUH) to the effective study of Islamic sources and teachings;
3. compare and contrast major developments in Islamic history across different periods;
4. critically analyse the significance of key events in Islamic history; and
5. discuss the relevance of the biographies of notable Muslim personalities to contemporary society.', 77::int),
    ('J125', 'ISS 001', 'History of Islam', 5, 1, 3, NULL::text[], 'At the end of this course, candidates should be able to:
1. classify the history of Islam into distinct periods and examine the defining features of each;
2. justify the relevance of the biography of Prophet Muhammad (PBUH) to the effective study of Islamic sources and teachings;
3. compare and contrast major developments in Islamic history across different periods;
4. critically analyse the significance of key events in Islamic history; and
5. discuss the relevance of the biographies of notable Muslim personalities to contemporary society.', 86::int),
    ('J125', 'ISS 002', 'Tawhīd and Ibādāt', 6, 1, 3, NULL::text[], 'At the end of this course, students should be able to:
1. analyse the various dimensions of Tawhīd (Unification of Allah), discuss the typologies of shirk (polytheism), and appraise the belief in Angels, Prophets, Scriptures, the Last Day, and Qadar;
2. compare the features of the primary and secondary sources of Sharī‘ah;
3. discuss the Islamic concept of ‘Ibādah and demonstrate proper performance of the various forms of Tahārah;
4. analyse the values and significance of Islamic rituals, including Salāt, Zakāt, Sawm, and Hajj; and
5. evaluate the rules governing Zawāj (marriage) and Ṭalāq (divorce). 90', 90::int),
    ('J125', 'ISS 003', 'Qur’ānic Studies', 7, 2, 3, NULL::text[], 'At the end of this course, candidates should be able to:
1. justify the authenticity of the Qur’ān as a divine scripture and differentiate between its revelation and compilation;
2. evaluate the necessity and significance of the Uthmānic copy of the Qur’ān;
3. distinguish between the Makkī and Madanī suwar;
4. interpret selected portions of Juz’ ‘Amma ; and
5. utilize Qur’ānic Arabic script and standard transliteration methods in reading and writing Arabic text of the Qur’ān. 93', 93::int),
    ('J125', 'ISS 004', 'Introduction to the Study of Hadīth', 8, 2, 3, NULL::text[], 'At the end of this course, candidates should be able to:
1. distinguish between Hadīth and Sunnah;
2. classify Hadīth into various categories and analyse their basic forms;
3. discuss the historical process leading to the emergence of Hadīth literature;
4. explain key terms used in the Science of Hadīth (‘Ulūm al-Hadīth); and
5. interpret selected Ahādīth . 95', 95::int),
    ('J126', 'LIT 001', 'Introduction to Drama', 1, 1, 3, NULL::text[], 'At the end of the course students should be able to:
i. read actively, discuss thoughtfully, respond personally, and write critically about a range of dramatic texts; ii. compare and contrast major theatrical movements in drama within their historical and cultural contexts; iii. identify and analyse the major elements of drama, including plot, character, setting, dialogue, symbolism, theme, and spectacle; and iv. identify and analyse the major genres of drama, including tragedy, comedy, and tragicomedy.', 101::int),
    ('J126', 'LIT 002', 'Introduction to Prose Fiction', 2, 1, 3, NULL::text[], 'At the end of this course, candidates should be able to:
i. read and critically analyse prose fiction written in diverse time periods, styles, and tones; ii. situate writers and narratives within their social, political, and historical contexts; iii. use direct textual evidence effectively to support arguments and integrate such evidence coherently in their writing; iv. appreciate literature as an art form that raises valuable questions rather than provides fixed answers; and v. formulate insightful and challenging questions that lead to persuasive critical arguments.', 103::int),
    ('J126', 'LIT 003', 'Introduction to Poetry', 3, 2, 3, NULL::text[], 'At the end of this course, candidates should be able to:
i. discuss the themes and styles of a range of poems with confidence and clarity ii. read and analyse selected poems in an informed and critical manner; iii. identify the intention and effect of poetic devices such as rhyme, rhythm, and imagery; iv. appreciate how the formal elements of language and genre contribute to meaning in poetry; and v. demonstrate awareness of a variety of poetic traditions across different cultures and periods. 105', 105::int),
    ('J126', 'LIT 004', 'Literary Appreciation & Practical Criticism', 4, 2, 3, NULL::text[], 'At the end of the course, the candidate should be able to:
i. compare and contrast two or more unfamiliar extracts from different literary texts; ii. distinguish between various genres and identify the different purposes of writers, including the distinction between fact and fiction; iii. examine and appreciate the literary features of prose and poetry, and enjoy the aesthetic effect of a passage or poem as a whole; 107 iv. demonstrate understanding of how writers create effects through language, form, and structure; and v. develop and express personal responses to texts through close, detailed, and coherent written analysis.', 107::int),
    ('J127', 'MUS 001', 'Basic Theory of Music', 1, 1, 3, NULL::text[], 'At the end of this course, candidates should be able to:
i. define music and describe the qualities of musical sounds; ii. identify musical notes and rests, including their placement on the lines and spaces of the staff, as well as ledger lines; iii. list and explain the function of accidentals in music; iv. draw and perform major, minor, and chromatic scales (with and without key signatures), and explain and apply the concept of meter, including simple and compound time signatures; and v. describe chords and triads (major, minor, diminished, and augmented); and define selected musical terms, signs, and abbreviations.', 113::int),
    ('J127', 'MUS 002', 'A Survey of African Music', 2, 1, 3, NULL::text[], 'At the end of this course, candidates should be able to:
i. define African music and describe its basic characteristics; ii. explain the functions of African music in society; iii. identify the theories and key components of African music, and describe the relationship between dance forms and music; iv. define and explain popular music forms in Africa; and v. describe African musical instruments and their usage in performance and cultural contexts. 117', 117::int),
    ('J127', 'MUS 003', 'Basic Musicianship', 3, 2, 3, NULL::text[], 'At the end of this course, candidates should be able to:
1. identify and notate basic musical intervals;
2. sight-read simple harmonic tunes accurately;
3. transcribe simple melodic tunes into tonic sol-fa notation; and
4. distinguish between different pitch levels and tonal qualities on musical instruments. 120', 120::int),
    ('J127', 'MUS 004', 'Music Appreciation', 4, 2, 3, NULL::text[], 'At the end of this course, candidates should be able to:
1. define music as both an art and a science;
2. identify and describe the properties of musical sound;
3. explain the types of listening, develop basic listening skills, and describe the eras and notable composers of Western music;
4. list and explain the basic structure and forms of music; and
5. define popular music in Africa and other world cultures.', 122::int),
    ('J128', 'VSA 001', 'Art History', 1, 1, 3, NULL::text[], 'At the end of this course, the candidates should be able to:
i. identify a broad range of paintings, sculptures, installations and other artistic creations from diverse world cultures; ii. demonstrate knowledge of the trajectories of various artists and major art events across the globe; iii. critically evaluate different artistic styles and movements; and iv. assess the historical, social, and cultural contexts of art production. Course content S/N TOPICS SUB-TOPICS DETAILS & NOTES
1. Origin of Art and Cave art, Prehistoric Periods, A general survey course the Prehistoric Paleolithic, Mesolithic and Neolithic that would deal with an Periods periods introduction to European and African Art- Art of the
2. Nubian, Egyptian, Characteristics of Nubian and renaissance period, various Greek and Roman Egyptian, Greek and Roman Arts artistic movements, Arts cubism, expressionism, Medium, Characteristics and Functions. post modernism, modernism, impressionism etc.
3. Art Movement Renaissance Art of Europe, A general introduction to Abstract Expressionism, Surrealism, the arts of Africa- brief Cubism, Abstraction, Pop Art, studies of selected African Minimal Art, Negritude, Natural and European artists and Synthesis, Ulism and Onaism movements. Conceptual Art, Expressionism Issue- based art and globalization A short assessment of
4. African Art of the Masking traditions, Classical various artistic movements, Sub-Saharan sculptures from Nigeria, Nok, Igbo- heritage sites, museums, Region Ukwu, Ife, Benin, Tsoede, Owo, and monuments and art such other artistic traditions workshops in Africa. 128
5. Art Personalities in Pablo Picasso, Paul Cezanne, Nigeria and Across Michelangelo Bounarroti, Bruce Identification of selected the Globe Onobrakpeya, Yussuf Grillo, art works and art Malangatana Valente, David personalities across the Koloane, El Salahi, Skunder globe and their Boghosian, Sokari Doughlas Camp, specializations. Yinka Shonibare, Aina Onabolu, Akin Lasekan, Ben Enwonwu, Uche Okeke, Demas Nwoko, Clara Ugbodaga Ngu, Ladi Kwali, Kolade Oshinowo, Jimoh Buraimoh, Nike Davies-Okundaye, Victor Ekpu, Pat Oyelola, Jelili Atiku, Jerry Buhari, Abayomi Barbar, Dele Jegede, Akin Onipede, Sola Ogunfunwa, John Adenle, Sola Ogunfuwa, Joseph Azi, El-Anatsui, Adams Ohams, Erabor Emokpae, Taiwo Olaniyi, Bruce Onobrakpeya, Adagogo Green, Billy Rose, Amaize Ojekere, Kunle Adeyemi, Ebun Aleshinloye, Adams Ohams, Jimoh Ganiyu, Sunmi Smart Cole, and such other art Personalities,
6. Major museums, Federal, states and private museums, A short assessment of galleries, art art galleries, art workshops and various artistic heritage workshops and historical sites sites, museums, historical sites in monuments and art Nigeria workshops in Africa. VSA 002: Two Dimensional Design Specific Objectives At the end of this course, candidates should be able to:
i. interpret the principles and elements of design as it applies to two-dimensional art; 129', 127::int),
    ('J128', 'VSA 002', 'Two Dimensional Design', 2, 1, 3, NULL::text[], 'At the end of this course, candidates should be able to:
i. interpret the principles and elements of design as it applies to two-dimensional art; 129 ii. use colours effectively and appropriately in design composition; iii. demonstrate skills in the use of digital software packages in art and design production; and iv. explore the use of a variety of materials or media and processes in two dimensional design.', 129::int),
    ('J128', 'VSA 003', 'Three Dimensional Design', 3, 2, 3, NULL::text[], 'At the end of this course, candidates should be able to:
i. demonstrate both theoretical and practical understanding of three-dimensional art forms; ii. identify and apply appropriate modelling tools and materials; and iii. create and model three-dimensional forms using clay and other media; iv. demonstrate good knowledge and use of the elements and principles of three-dimensional design. 131 Course content S/N TOPICS SUB-TOPICS DETAILS & NOTES
1. Ceramics Methods of using clay for hand This course is an built- slab, coil, pinching introduction to three-methods, dimensional art Casting- press and slip casting forms such as Wheel throwing techniques. ceramics and Drying and firing. Use of slip sculpture. and oxides for decorating and Candidates will be painting. taught the various Glazing and firing techniques. materials and methods of Ceramics
2. Sculpture Materials and methods in and Sculpture. They sculpture also learn the Modeling simple forms and terminologies and relief sculpture take part in the Studies in sculpture in the round production of Casting techniques in sculpture selected practical Metal assemblage assignments. Installation art. VSA 004: Decorative Arts & Other Craft Traditions Specific Objectives At the end of this course, candidates should be able to:
i. identify various craft traditions; and identify local resources used in craft making and factors precipitating local craft practice; ii. identify materials that can be recycled, upcycled and reused for decorative art and craft production; and iii. produce a practical project in the decorative arts or crafts peculiar to any culture the student is familiar with. 132', 131::int),
    ('J128', 'VSA 004', 'Decorative Arts & Other Craft Traditions', 4, 2, 3, NULL::text[], 'At the end of this course, candidates should be able to:
i. identify various craft traditions; and identify local resources used in craft making and factors precipitating local craft practice; ii. identify materials that can be recycled, upcycled and reused for decorative art and craft production; and iii. produce a practical project in the decorative arts or crafts peculiar to any culture the student is familiar with. 132', 132::int),
    ('J129', 'YOR 001', 'Language I: Yorùbá Phonology', 5, 1, 3, NULL::text[], 'At the end of this course, candidates should be able to:
i. define and explain language and linguistics; ii. identify and describe Yorùbá speech sounds — vowels and consonants; iii. define and identify the types of Yorùbá syllable structures; iv. explain and illustrate phonological processes such as vowel harmony, vowel assimilation, vowel coalescence, and deletion in utterances; v. identify and explain the different Yorùbá tones; and vi. transcribe Yorùbá words both phonetically and phonemically.', 137::int),
    ('J129', 'YOR 002', 'Literature I: Oral Yorùbá Literature', 6, 1, 3, NULL::text[], 'At the end of this course, candidates should be able to:
i. identify the three subdivisions of oral literature: poetry, prose, and drama; ii. describe the nature of oral literature, including its oral and transcribed forms; iii. explain the scope of oral literature; iv. classify and categorise the various types of oral literature, and v. discuss the features of oral literature. 139', 139::int),
    ('J129', 'YOR 003', 'Language II: Yorùbá Grammar', 7, 2, 3, NULL::text[], 'At the end of this course, candidates should be able to:
i. identify the lexical and grammatical categories (parts of speech) of Yorùbá words and their features; ii. describe and explain the different Yorùbá phrase types; iii. classify the various sentence types; iv. discuss different types of clauses; and v. explain the syntactic functions of all parts of speech in Yorùbá sentences.', 141::int),
    ('J129', 'YOR 004', 'Literature II: Written Yorùbá literature', 8, 2, 3, NULL::text[], 'At the end of this course, candidates will be able to:
i. identify the various genres of written Yorùbá literature—poetry, prose, and drama; ii. describe the nature of written Yorùbá literature, tracing its development (colonial, missionary, societies influence), its performance and transcription as exemplified by selected works of early authors (Ọba kò so); iii. explain the scope and thematic concerns of written Yorùbá literature; 142 iv. explain the literary techniques of written Yorùbá literature; and v. discuss the relevance of written Yorùbá literature (poetry, prose, and drama) to the individual and society at large.', 142::int),
    ('J131', 'ACC 001', 'Basic Financial Accounting', 1, 1, 3, NULL::text[], 'At the end of this course, candidates should be able to:
1. define and explain basic accounting terms, concepts, and conventions;
2. record financial transactions in the books of original entry and post them to the ledger up to the extraction of a trial balance; and correction of errors;
3. prepare a control account;
4. reconcile the Cash Book balance with the Bank Statement balance;
5. demonstrate an understanding of the evolution, structure, roles, and functions of Accounting standard bodies;
6. determine and analyze the application of IAS1/IFRS18, IAS 2 and IAS 16;
7. evaluate end-of-period adjustments and prepare revised trial balance;
8. prepare financial statements for sole proprietorships, partnerships, not-for-profit organisations, and limited liability companies;
9. prepare manufacturing account; and
10. prepare financial statements from single entry and incomplete records.', 149::int),
    ('J131', 'ACC 002', 'Basic Cost and Management Accounting', 2, 1, 3, NULL::text[], 'At the end of this course, candidates should be able to:
1. explain the concepts, principles and classification of cost accounting;
2. compute material pricing and valuation; and determination of inventory management;
3. determine appropriate labour remuneration method and labour rate;
4. incorporate overhead cost into product cost for pricing purposes;
5. prepare process costing and the determination of abnormal losses or gains;
6. post into cost ledgers and extract a trial balance;
7. value inventory using marginal, absorption and standard costing techniques;
8. analyze and predict cost behaviour as output and market conditions vary, and determine the resulting impact on profit; and
9. prepare functional budget and simple cash budget without discount. 156', 156::int),
    ('J131', 'ACC 003', 'Basic Auditing', 3, 2, 3, NULL::text[], 'At the end of this course, candidates should be able to:
1. explain the historical development of accounting and auditing
2. explain the nature, scope, principles and fundamental concepts of auditing;
3. demonstrate a basic understanding of the audit framework process;
4. exhibit awareness of key ethical concepts such as audit independence, objectivity, integrity, confidentiality, due care, and professional competence;
5. explain the concept of a “true and fair view” (fair presentation) in relation to the expression of an audit opinion;
6. demonstrate an understanding of the preparation of an audit report; and
7. discuss relevant issues in accounting and auditing', 162::int),
    ('J131', 'ACC 004', 'Basic Principles of Nigerian Taxation', 4, 2, 3, NULL::text[], 'At the end of this course, candidates should be able to:
1. discuss the nature, structure, and functions of the Nigerian tax administration;
2. distinguish among the various types of taxes administered by different tax authorities in Nigeria; and
3. compute taxes payable by applying the current corporate tax rate.', 164::int),
    ('J132', 'BUS 001', 'Business and its Environment', 1, 1, 3, NULL::text[], 'At the end of this course, the students should be able to:
i. explain the purpose and nature of business activity, including the environmental factors that influence and constrain business behaviour; and 169 ii. describe business activities as integrated processes that function as a whole rather than as isolated components. iii. discuss the roles of government in business iv. understand the concept of entrepreneurs and entrepreneurship processes v. explain different forms of business enterprises and what lead to their failures vi. identify business stakeholders and their responsibilities', 169::int),
    ('J132', 'BUS 002', 'Management I', 2, 1, 3, NULL::text[], 'At the end of this course, the students should be able to:
i. explain the concept of people in organization and marketing, 172 ii. describe the opportunities and constraints in relation to managing people in organizations, iii. explain the importance of marketing to businesses and how it influences their competitiveness, iv. explain the various theories of motivation v. discuss various schools of management thoughts vi. understand various leadership styles and theories of leadership', 172::int),
    ('J132', 'BUS 003', 'Finance and Accounting', 3, 2, 3, NULL::text[], 'At the end of this course the students should be able to:
i. discuss the nature of financing ii. enumerate the importance of the management of finance, the keeping and analysis of accounts, and the assessment of businesses financial performance, iii. understand the fundamental of accounting concepts and principles iv. apply accounting information to decision making. 174 v. use various financial ratios to take appropriate financial decisions', 174::int),
    ('J132', 'BUS 004', 'Management II', 4, 2, 3, NULL::text[], 'At the end of this course the students should be able to. i. explain strategic management ii. describe process of strategic management and decisions in managing a business in all sectors iii. link strategies to other functional areas of a business, such as marketing and human resource, iv. emphasizing strategic implementation and. Evaluation 176 v. discuss the concept of green management and implications of climatic changes on business operation', 176::int),
    ('J133', 'ECN 001', 'Principles of Economics I', 1, 1, 3, NULL::text[], 'At the end of this course, candidates should be able to:
i. explain basic economic concepts relevant to solving decision-making problems of households, firms and government; 181 ii. discuss and apply fundamental tools and methods of economic analysis in economic reasoning; iii. explain the theoretical foundations of households’ and firms’ behaviours in the market; iv. discuss the conditions for price determination and profit maximization', 181::int),
    ('J133', 'ECN 002', 'Principles of Economics II', 2, 1, 3, NULL::text[], 'At the end of this course, candidates should be able to:
i. explain macroeconomic relationships among the economic agents (households, firms and government) ii. discuss the measurement of national income and its relationships with multiplier and accelerator principles iii. explain the role of money and financial institutions on the national economy iv. discuss the structure and implications of government financing on the national economy 189', 189::int),
    ('J133', 'ECN 003', 'Applied Economics I', 3, 2, 3, NULL::text[], 'At the end of this course, candidates should be able to:
i. discuss the measurement and relationship between economic growth and economic development; ii. explain the structure of the economies of Nigeria relative to other comparable countries; iii. evaluate the relationship between population growth and real production in developing countries such as Nigeria; and iv. apply the theories of international trade to developing economies such as Nigeria 192', 192::int),
    ('J133', 'ECN 004', 'Applied Economics II', 4, 2, 3, NULL::text[], 'At the end of this course, candidates should be able to:
i. explain the role of government intervention in the economy; ii. apply basic concepts to contemporary macroeconomic issues iii. identify and explain how government policies can be used to address macroeconomic problems; and iv. discuss the roles and functions of major international economic institutions.', 196::int),
    ('J134', 'GRY 001', 'Elements of Physical Geography', 1, 1, 3, NULL::text[], 'At the end of the course, the students should be able to:
1. describe the major spheres of the physical environment;
2. analyze and appreciate the interactions and interconnections among the component spheres of the physical environment;
3. explain the complexity and dynamic nature of the physical environment;
4. discuss the fundamental processes operating at various spatial and temporal scales within the physical environment; and
5. explain the concept of environmental hazards and the principles of sustainable management of the physical environment.', 204::int),
    ('J134', 'GRY 002', 'Fundamentals of Human Geography', 2, 1, 3, NULL::text[], 'At the end of the course, students should be able to:
1. highlight the distinctive characteristics of different human environments;
2. demonstrate an understanding of the concepts, processes, and challenges involved in explanation, including data collection and analysis, in human geography;
3. identify the nature, significance, and limitations of various approaches to the study of human environments;
4. explain the dynamic interactions between humans and their environments; and
5. describe the complex human environment as a system of interrelated sub-systems shaped by diverse human activities within their spatial and cultural contexts.', 209::int),
    ('J134', 'GRY 003', 'Map Reading / Interpretation and GIS', 3, 2, 3, NULL::text[], 'At the end of the course, students should be able to:
1. handle and evaluate different types and sources of geographic data;
2. collect, record, interpret, and synthesize information from both primary (fieldwork) and secondary sources;
3. develop an aptitude for accuracy and objectivity in collecting, recording, processing, analyzing, interpreting, and reporting spatial data;
4. understand the field and practical aspects of geography in order to acquire skills for analyzing, interpreting, and appreciating the physical and human environments; and
5. demonstrate competence in data collection and analysis. 215', 215::int),
    ('J134', 'GRY 004', 'Regional Geography', 4, 2, 3, NULL::text[], 'GRY 004 (the regions covered in the 219 course include: Nigeria, West Africa, Africa & North America)
2. Location of the Location Location, Size, Geopolitical Regions Divisions of Nigeria, West Africa, Africa, and North America.
3. Physical Climate Climatic characteristics of Environment of Nigeria, West Africa, Africa the Regions and North America Relief and Drainage Major landforms and river systems in the regions Vegetation and Soils Vegetation belts and soil types of Nigeria, West Africa, Africa, and North America
4. Human Population Population distribution, and Environment of density of Nigeria, West the Regions Africa, Africa, and North America Settlements settlement patterns: Rural and urban settlements and functions within the regions Culture Definition, types and different major Ethnicity, Language and Religion of Nigeria, West Africa, Africa, and North America.
5. Spatial The Concept of Meaning, Types and Organization Spatial Organization Importance of Spatial Organization 220
6. Geographical Region and its types • Meaning of Region; Region • Types of Region (Homogenous, Functional & Perceptual Regions);
• Definition of Regional Development;
• Regional Disparities in Social and Economic Development within Countries);
• Causes and consequences of regional disparity within countries.
7. Regional Economic • Economic activities in Economy Development Nigeria, West Africa, Africa, and North America. Agriculture • Agricultural activities and regions within Nigeria, West Africa, Africa, and North America.
• Importance and problems of agriculture in the different regions; Mining • Mineral resources and mining activities in Nigeria, West Africa, Africa and North America;
• Importance and problems of mining within the different regions Industry • Industrial development and industrial regions in Nigeria, West Africa, Africa and North America;
• Importance and problems of each region; Trade and Transport • Trade Flows, Trading Patterns and transportation 221 networks within and between the regions; •', 219::int),
    ('J135', 'GOV 001', 'Elements of Government and Politics', 1, 1, 3, NULL::text[], 'At the end of the course, the candidates are expected to:
1. define government and politics;
2. explain the methods and approaches to the study of government and politics;
3. identify the key institutions and processes within their political environment. 226 Course content S/N TOPIC SUB-TOPIC DETAILS & NOTES 1 Basic Concepts and Definitions of The candidates are expected to Nature of government and politics, have deep knowledge and Government and understanding of government Rationale for studying Politics and politics for general government as an application to issues in the academic discipline, political structure, institutions and processes. . Power, Influence, Authority, Legitimacy, Sovereignty, Nation, State, Nation-State, Political Culture, Political Socialization, Political Participation 2 Scope and The candidates are expected to relationship with understand the meaning and other disciplines nature of:
i. Political Theory ii. Political Economy iii. International Relations iv. Public Administration v. Local Government vi. Comparative Politics vii. Peace and Conflict Studies viii. Security Studies and Development Studies. 227 Relationship between the i. History study of ii. Philosophy government/politics and iii. Law other academic iv. Economics disciplines. v. Geography vi. Sociology/ anthropology vii. Psychology 3 Methods/Approaches i. Philosophical/Nor Arguments on the scientific to the Study of mative status of politics. government and ii. Institutional/legal politics. iii. Historical iv. Comparative v. Qualitative vi. Quantitative vii. Scientific viii. Behavioural ix. Empirical. 4 The State, Structure Definition, Purpose and and Types of Functions of the Modern Government state, Theories of the State, Characteristics of the State, Types of State. Structure of Government i. Executive ii. Legislature iii. Judiciary Functions, relationships, strengths and weaknesses of the executive, legislature and judiciary. 228 Types of government. i. Democracy ii. Monarchy iii. Oligarchy iv. Aristocracy', 226::int),
    ('J135', 'GOV 002', 'Ideologies & Processes of Government and Politics', 2, 1, 3, NULL::text[], 'At the end of the course, the candidates should be able to:
1. describe the major political ideologies and theories;
2. explain the nature, functions, and types of political parties, party systems, and pressure groups;
3. describe the concepts of public opinion, propaganda, elections, and electoral systems; and
4. discuss the principles and scope of public administration and international relations. 230', 230::int),
    ('J135', 'GOV 003', 'Nigerian Government and Politics', 3, 2, 3, NULL::text[], 'At the end of the course, the candidates should be able to:
1. describe the various pre-colonial and colonial political systems in Nigeria;
2. explain the nature of Nigerian legal system
3. discuss the major issues in Nigerian government and politics;
4. examine the nature, features, and impact of military rule in Nigeria. 234', 234::int),
    ('J135', 'GOV 004', 'African Government and Politics', 4, 2, 3, NULL::text[], 'At the end of the course, the students should be able to:
1. describe the political, social, and economic structures of Africa before European invasion;
2. discuss the processes and consequences of European invasion and colonization of Africa;
3. explain the various colonial systems of administration practiced in Africa;
4. analyze the nationalist movements in West Africa and their impact on the struggle for independence; and
5. discuss critical issues in African government and politics.', 238::int),
    ('J151', 'AGR 001', 'Agronomy and Crop Protection', 1, 1, 3, NULL::text[], 'At the end of this course, candidates should be able to:
i. define soil and explain weathering processes; and discuss the significance of soil texture, structure and soil pH; ii. explain the source of negative charges on clay, humus and colloids; and emphasize the significance of Cation Exchange Capacity (CEC) and Anion Exchange Capacity (AEC); iii. describe methods of water and soil conservation e.g. dam, harvesting water from roofs, water weirs and conservation tillage practices; iv. define and classify seeds; discuss the uses and maintenance of seeds, management of seedling nurseries in relation to thinning, hardening, root pruning, pests and disease control; v. define the term farm mechanization and discuss types, merits and demerits of farm mechanization in Nigeria; Course content S/N TOPICS SUB-TOPICS DETAILS & NOTES 1 Soil Physics, Soil physical Definition, Soil formation, Weathering Soil properties processes, composition and soil physical Chemistry and properties e.g. soil texture, soil structure, soil Soil Biology capillarity, bulk density, porosity, soil color etc. Soil Chemical Soil acidity and alkalinity; causes and effects Properties on crops, soil Ph, cation exchange capacity (ECE) and Anion Exchange Capacity (AEC). Correction of soil acidity 246 S/N TOPICS SUB-TOPICS DETAILS & NOTES Soil Fertility Soil macro elements (N, P, K, etc.) and micro nutrients (Mo, B, Zn, etc.). Nitrogen Cycle. Organic matter composition and importance to agriculture. Soil improvement through the application of Organic fertilizers. 2 Soil & Water Soil and Water Definition, methods and importance of soil Conservation Conservation conservation. Methods Methods of controlling soil erosion (biological, mechanical and cultural). Methods of water conservation (dams, harvesting from roofs water weirs, mulching). Irrigation Types of irrigation systems (surface, overhead and underground systems). Importance of irrigation to agricultural production in Nigeria. 3 Crop Plant Plant growth, Study of the cell and its contents. Genetics development and Cell division and enlargements leading to improvement growth (mitosis). Meiosis, pollen structure, pollen formation and ovule development. Seed dormancy, pre-germination treatment, viability test, control and seed germination experiments. Mendelian laws of inheritance and processes of crop improvement. 247 S/N TOPICS SUB-TOPICS DETAILS & NOTES 4 Crop Plant Water and Mechanism of water uptake Metabolism, Nutrient Uptake (Osmosis/Diffusion) and nutrient uptake, Anatomy and (Active transport system). Physiology Plant Anatomy, Plant parts identification. Photosynthesis Meaning and importance of photosynthesis, and Respiration factors affecting photosynthesis e.g. carbon (IV) oxide, compensation point. Relationship between respiration and photosynthesis. Role of Ad', 246::int),
    ('J151', 'AGR 002', 'Animal Science and Production', 2, 1, 3, NULL::text[], 'At the end of this course, candidates should be able to:
i. classify livestock feed in terms of energy, fats and protein they give; and describe the structure of carbohydrates, protein, lipids, nucleic acids including functions of vitamins and minerals; 249 ii. calculate conception, calving, farrowing, kidding and mortality rates; iii. explain the following terms as used in animal breeding and genetics (gene, locus, chromosome, genotype, phenotype, dominance, recessive, epistasis, heterozygous, homozygous, variation and heritability); iv. identify locally available breeds of livestock, classify diseases and parasites affecting them. v. enumerate the appropriate methods of processing, storing and marketing animal products. Course content S/N TOPICS SUB-TOPICS DETAILS & NOTES 1 Animal Animal Forms and classification of major farm Production husbandry animals in West Africa, General terminology in animal production, Anatomy of farm animal, Livestock Management. 2 Animal Animal Classes of livestock feed(Roughages, Metabolism Nutrition succulents, concentrates). Feed digestibility and calculation of feed digestibility. Feed ration and ration formulation. 3 Reproduction in Physiology of Urinogenital systems of farm animals. Farm Animals Farm Animals Fertility and infertility in Farm Animals (male and female).Site of fertilization in female farm animals. 4 Animal Animal Mendelian Laws of Heredity. Genetics Breeding Inbreeding and Crossbreeding:
Advantages and Disadvantages. Improvement of farm animals. Terminologies in animal breeding. 250 S/N TOPICS SUB-TOPICS DETAILS & NOTES 5 Animal Animal Health Identification and Classification of Pathology and Important Parasites and Diseases of Control Farm Animals. Economic Importance of Diseases and Parasites of Farm Animals. Pests and Disease Transmission and Control. 6 Animal Uses of Animal Processing, Storage and Marketing of Products Parts fish, meat, egg, milk, wool, leather etc. AGR 003: Wildlife, Aquaculture and Agro-Forestry (3 Units) Specific Objectives At the end of this course, candidates should be able to:
i. define and explain the principles of agro forestry, identify and enumerate types of wild animals and timber tree species in Nigerian forests; ii. explain the economic, social and ecological importance of wildlife, aquaculture and forests; iii. demonstrate timber harvesting and preservation techniques; and describe methods of harvesting wildlife e.g. trapping, shooting, and netting; iv. discuss fishery growth, environment and economy; v. explain desertification and deforestation, causes, effects and control; and explain the concept of climate change, causes, effects and mitigation. vi. define agricultural ecology, ecological zones in Nigeria, types of agricultural system in Nigeria and environmental pollution. Course content S/N TOPICS SUB-TOPICS DETAILS & NOTES 1 Social, Importance of Definition of forestry, Economic, Economic and Forestry and social and ecological importance of Environmental Wildlife to the wildlife and forests. Forestry Nigerian Economy. 251', 249::int),
    ('J151', 'AGR 003', 'Wildlife, Aquaculture and Agro-Forestry', 3, 2, 3, NULL::text[], 'At the end of this course, candidates should be able to:
i. define and explain the principles of agro forestry, identify and enumerate types of wild animals and timber tree species in Nigerian forests; ii. explain the economic, social and ecological importance of wildlife, aquaculture and forests; iii. demonstrate timber harvesting and preservation techniques; and describe methods of harvesting wildlife e.g. trapping, shooting, and netting; iv. discuss fishery growth, environment and economy; v. explain desertification and deforestation, causes, effects and control; and explain the concept of climate change, causes, effects and mitigation. vi. define agricultural ecology, ecological zones in Nigeria, types of agricultural system in Nigeria and environmental pollution. Course content S/N TOPICS SUB-TOPICS DETAILS & NOTES 1 Social, Importance of Definition of forestry, Economic, Economic and Forestry and social and ecological importance of Environmental Wildlife to the wildlife and forests. Forestry Nigerian Economy. 251 S/N TOPICS SUB-TOPICS DETAILS & NOTES 2 Principles of Important Definition, principles and types of Agroforestry Agroforestry agroforestry. Systems in Nigeria Concept of forest, forestry and silviculture. Definition and practice of agroforestry. Systems of agroforestry (e.g. Agrosilvipastoralism, Agrosilviaquaculture, Agrosilviapiculture, Agrosilvimycology, Agrosilviheliculture, etc.,). The need for conserving our forests (sources of useful medicinal herbs, dyes, fibres, game animals which energize our rural economy). 3 Forestry and The Roles of Definition of climate change. Climate Forestry on Climate Causes, Mitigation and Adaptation Change Change Mitigation to Climate Change. Effects of Climate Change on Agriculture. 4 Forest, Wildlife and Forest Meaning of Wildlife, forestry Wildlife, Conservation/ Wildlife Conservation Methods. Ecotourism and Management Management Ecotourism potentials of Forest and Wildlife in Nigeria. Identification and Classification of Common Species of Wild Animals and Trees in Nigeria. 252 S/N TOPICS SUB-TOPICS DETAILS & NOTES Selective exploitation, Forest regulation, Afforestation, Regeneration, Taungya system, Enrichment planting, etc. 5 Deforestation Mitigation of Meaning of Deforestation and and Deforestation and Desertification. Desertification Desertification in Causes of Deforestation and Nigeria Desertification. Effects of Deforestation, Desertification and control. 6 Timber and Utilization of Shelter for wildlife, sources of Non-Timber Forest Resources cooking fuel, raw materials for Forest Products industries e.g. plywood, etc. Marketing of Forest Types of Forest Products and Products examples. Harvesting(timber),Processing, marketing and exportation of the forest products. 7 Aquaculture, Fish Production', 251::int),
    ('J151', 'AGR 004', 'Agricultural Economics & Extension', 4, 2, 3, NULL::text[], 'At the end of this course, candidates should be able to:
i. explain the principles of demand and supply of agricultural products and services including farm management; risks and uncertainties in Agriculture; ii. identify and discuss land tenure systems and their implications on Agriculture in Nigeria; iii. calculate and illustrate price break- even point and discuss decision making processes to determine profitability and sustainability of a crop/animal enterprise; iv. define marketing and explain perfect and imperfect competition in marketing; v. identify and explain problems of marketing agricultural products and government intervention; vi. explain the principles of agricultural extension, basic concepts and principles of rural sociology in Nigeria, agricultural innovation and communication techniques in extension; vii. explain Principles of Family and Consumer Sciences, Food Science and Technology. Course content S/N TOPICS SUB-TOPICS DETAILS & NOTES 1 Principles of Demand and Supply Definition of Agricultural Agricultural of Agricultural Economics, Principles of demand Economics Goods and Services and supply of agricultural products, simple demand and supply curves, illustration with diagrams, the elasticity of demand and supply. Law of diminishing returns, principles of economies of scale in agriculture and opportunity costs. 2 Agricultural Principles of Definition and Objectives of Extension and Agricultural Agricultural Extension. Management Extension Functions and principles of Agricultural Extension. Role of extension agents, methods of 254 S/N TOPICS SUB-TOPICS DETAILS & NOTES dissemination of improved technology; Agricultural Extension methods. Problems of effective extension programmes in Nigeria. Basic concepts and principles of rural sociology. Importance of rural communities and institutions, social stratification, social processes, and social changes in rural areas. Emergence and functions of leadership in rural communities. Agricultural extension teaching methods, aids, and their use. 3 Farm Land Tenure, Risk, Land tenure systems in Nigeria and Management Uncertainty and their implications to agriculture. Budgeting in Agri- Land use act of 1978, Business Business objectives in farming, risks and uncertainties in agriculture, budgeting in farming business. 4 Agricultural Marketing of Definition of agricultural Marketing Agricultural Produce marketing, characteristics of perfect and imperfect competition. Type of markets, perfect competition, monopoly, oligopoly etc. International trade agreements and their impact on marketing. Problems of marketing agricultural produce. Government intervention programmes in agriculture (support prices and subsidies). Cost analysis 255 S/N TOPICS SUB-TOPICS DETAILS & NOTES and functions. Concept of elasticities. Price theory and some applications. The components of agriculture in national income. Aggregate income, expenditure, investment, interest rate, savings, employment. Inflation; international trade, commodity agreements, and balance of payments. Money and banking. 5 Agricultural Importance of Definition of agricultural Accounting Agricultural accounting and finance; and Finance Accounting and Importance of farm accounting and Finance finance, common sources of farm credit, subsidy, loan, etc. 6 Principles of Historical Philosophy, scope, objectives and Family and development of historical development of family Consumer family and consumer and consumer sciences. Sciences, Food science Examination of basic human needs Science and with respect to food, clothing, Technology shelter, and health. Programme approaches in family and consumer sciences which will help meet these needs. Professional opportunities in family and consumer sciences. The role of a family and consumer sciences professional in today''s society. Definition and scope of food science and technology. Food distribution and marketing. Food and its functions. Food habits. Food 256 S/N TOPICS SUB-TOPICS DETAILS & NOTES poisoning and its prevention. Principles of food processing and preservation. Discussion of different preservation methods. Deterioration and spoilage of foods, other post- harvest changes in food. Contamination of foods from natural sources. Composition and structures of Nigerian/West African food; factors contributing to texture, colour, aroma, and flavour of food. Cost, traditional and ethnic influence of food preparation and consumption pattern. RECOMMENDED TEXTS
1. Anthony, Y., & Ezeinna, F.O. C. (1999). Introduction to Tropical Agriculture. Longman Publishers.
2. Jean, P. (1993). Animal Production in the Tropics. Macmillan Publishing Company.
3. Rice, R.P., Rice, L.W., & Tindall, H.D. (1990). Fruit and Vegetable production in Warm Climate. Macmillan Publishing Company.
4. Brady, N.C. (2017). The Nature and Properties of Soils (15th ed.). Pearson Education. ISBN: 978-0133254488
5. Bidwell, R.G.S. (1964). Plant Physiology. Macmillan Publishing Company.
6. David, C. and Trevor, Y. (1989). “Principles of Agricultural Economics”. Cambridge University Press
7. Iwena, O.A. (2018). Essentials of Agriculture for Senior Secondary Schools. Ogun State, Nigeria: Tonad Publishers Limited. ISBN: 978-978-52654-1-9
8. Okaro, E.U. (2016). Intensive Agricultural Science for Senior Secondary Schools. Upper New Market Road, Onitsha, Nigeria: Elites Publishers. ISBN: 978-978-803735-3-6 257
9. Akinsanmi, O. (2001). Senior Secondary Agricultural Science. England: Longman Group Limited. ISBN: 0582003407.
10. Avantina Sharma (2019).Textbook of food science and technology(3rd Edition). CBS Publisher and Distributions. SBN-13:978-9386478009.
11. Sharlen,L Kato(2007).Foundations of Family and Consumer Science. Publisher:
Goodheart-willcox.ISBN-139781590708125 258 SYLLABUS FOR SCI -J152 BIOLOGY 259 SYLLABUS FOR SCI -J152 BIOLOGY At the end of the series of courses, candidates should be able to:
1. describe the fundamental characteristics and levels of organization in living organisms;
2. explain the functional units of biological molecules and the principles of interactions among organisms;
3. apply basic statistical concepts in biological studies;
4. describe cells as the basic units of life and explain their roles in nature;
5. explain the applications of Genetics in the medical, industrial, and biotechnological sub-sectors of the economy;
6. discuss the diversity, characteristics, structure, functions, and taxonomy of living organisms, including microorganisms, plants, and animals;
7. enumerate the economic importance of living organisms;
8. describe the morphological and biochemical characteristics of microorganisms;
9. conduct laboratory and field practicals in Biology, Botany, Microbiology, and Zoology;
10. identify and explain the basic concepts of ecology;
11. explain the role of evolution in the hierarchical classification of living organisms, with reference to major evolutionary theories; and
12. define basic Genetic terminologies and state Mendelian laws of inheritance. FIRST SEMESTER COURSES BIO 001: GENERAL BIOLOGY (3 UNITS) BIO 002: BOTANY (3 UNITS) SECOND SEMESTER COURSES BIO 003: MICROBIOLOGY (3 UNITS) BIO 004: ZOOLOGY (3 UNITS) 260 COURSE DESCRIPTION BIO 001: GENERAL BIOLOGY Specific Objectives At the end of the course, the candidates should be able to:
1. explain the nature of living organisms and the structure and functions of biological molecules;
2. discuss the cell as the fundamental unit of life and describe the levels of organization in living organisms;
3. explain biological methods and their applications, including Biostatistics, Taxonomy, and Nomenclature;
4. discuss the principles of genetics, variation, and heredity; and
5. conduct laboratory and field practicals in biology.', 254::int),
    ('J152', 'BIO 001', 'General Biology', 1, 1, 3, NULL::text[], 'At the end of the course, the candidates should be able to:
1. explain the nature of living organisms and the structure and functions of biological molecules;
2. discuss the cell as the fundamental unit of life and describe the levels of organization in living organisms;
3. explain biological methods and their applications, including Biostatistics, Taxonomy, and Nomenclature;
4. discuss the principles of genetics, variation, and heredity; and
5. conduct laboratory and field practicals in biology.', 261::int),
    ('J152', 'BIO 002', 'Botany', 2, 1, 3, NULL::text[], 'At the end of this course, candidates should be able to:
1. discuss the general characteristics of plants;
2. explain the taxonomy and classification of lower and higher plants;
3. discuss plant biodiversity and the principles of plant conservation;
4. explain plant structures, functions, and physiological processes; and
5. enumerate the economic and ecological importance of plants.', 265::int),
    ('J152', 'BIO 003', 'Microbiology', 3, 2, 3, NULL::text[], 'At the end of this course, candidates should be able to:
1. discuss the history and discovery of microorganisms;
2. describe the different types of microorganisms and their taxonomic classifications;
3. explain the cellular structure, morphology, and biochemical characteristics of microorganisms;
4. explain microbial genetics and their applications in biotechnology; and
5. enumerate the economic importance of microorganisms.', 270::int),
    ('J152', 'BIO 004', 'Zoology', 4, 2, 3, NULL::text[], 'At the end of this course, candidates should be able to:
1. discuss the general characteristics of the Kingdom Animalia;
2. explain the taxonomy and classification of invertebrates and vertebrates;
3. discuss the diversity of animal species;
4. explain the major physiological processes in animals; and
5. enumerate the economic and ecological importance of animals.', 272::int),
    ('J153', 'CHM 001', 'General Chemistry', 1, 1, 3, NULL::text[], 'At the end of this course, candidates should be able to:
1. apply appropriate scientific quantities and units in problem-solving.
2. perform statistical analyses of experimental data;
3. analyze mass spectra to determine relative abundances and relative atomic masses.
4. determine empirical and molecular formulae from experimental data; and
5. describe the development of modern atomic theory and structure.
6. identify the characteristics of acids, bases, and salts, and solve problems based on their quantitative relationship
7. use the VSEPR theory to determine the shapes of simple molecules Course content S/N Topic Sub-topic Details & Notes 1 Measurement Units of Measurement Basic S.I. Units, derived units, conversion of units, significant figures. Data analysis Precision and accuracy, errors (systematic and random errors). Error calculations (Standard deviation, relative error, absolute error, and percentage relative error). 2 Mole concept Atomic masses Isotopy. Use of mass spectrometry in the determination of Relative Atomic Mass. Calculation of relative abundances and isotopic masses. 281 S/N Topic Sub-topic Details & Notes The mole Definitions of the mole based on 12 C and Avogadro’s constant. Calculation based on Avogadro’s constant. Relative Molecular Mass. Empirical and molecular Definition and calculations of formula Empirical and Molecular formulae from percentage composition by mass and combustion data. Stoichiometry Definition and calculations of molarity, molality, mole fraction, and mass concentration. Standard solutions Primary and secondary standard. Preparation of standard solutions, serial dilution. 3 Atomic structure Discovery of sub-atomic Shortcomings of Dalton’s atomic particles theory. Various experiments that led to the discovery of neutrons, protons, electrons, and nuclei [Cathode ray, Millikan''s cathode ray, Rutherford and Chadwick experiment]. Planck’s theory Black body radiation, photoelectric effect, quantisation of energy. Bohr’s theory Bohr’s assumption, atomic spectra of hydrogen, and determination of spectral lines, determination of ionisation energy from line spectra (when n=∞). Wave theory of the atom Particle wave duality. Atomic orbitals, quantum numbers (n, l, m, and s). Including relation to energy level, degeneracy, and', 281::int),
    ('J153', 'CHM 002', 'Physical Chemistry', 2, 1, 3, NULL::text[], 'At the end of this course, candidates should be able to:
1. describe the properties of different states of matter
2. state the assumptions of the kinetic theory of ideal gases.
3. distinguish between ideal and real gases;
4. apply Hess’s Law to construct simple energy cycles and perform related calculations.
5. describe different types of solutions and the conductance of electrolyte solutions
6. write and use redox equations to construct electrochemical cells from relevant half-equations; and
7. use experimental data to deduce rate laws and determine the order of reactions. Course content S/N Topic Sub-Topic Details & Notes 1 Kinetic Theory of Nature of Matter Definition of Matter, State of Matter Matter, Properties of State of Matter Phase and phase Interconversion between the three diagrams states of matter. Interpretation of 285 S/N Topic Sub-Topic Details & Notes the phase diagram for one component system. Kinetic Molecular Gas Laws and calculations Theory of Gases involving Boyle’s, Charles’, Avogadro’s law, Dalton’s, Graham’s laws, and Gay Lussac’s law. Kinetic theory of gases (assumptions only). Calculations Ideal and Real Gases involving general and Ideal gas equations. Gas densities and molar mass. Boltzmann’s distribution of molecular speed, Mean, Root-Mean square, and most probable Velocities. Real gases deviation from ideal gas behaviour, Van der Waals’ equation.
2. Solutions Types of Solutions Definition of solution, Types including saturated, unsaturated, super saturated. Ideal and Non-Ideal Definition of ideal solutions, Solutions Raoult’s Law, and its Deviations. Colligative Lowering of vapour pressure, Properties depression of freezing point, elevation of boiling point, and osmotic pressure. Determination of molar masses using Colligative properties. (The derivation is not required.) 3 Thermochemistry Enthalpy Change Exothermic and endothermic changes. Definition of enthalpy changes for processes (combustion, neutralization, hydration, formation, solution, and atomization) under standard conditions. 286 S/N Topic Sub-Topic Details & Notes Hess’s Law State Hess’s law calculation based on Hess’s law and the construction of energy cycles based on Hess’s law. Born-Haber cycle for and carry out calculation of lattice energy. s based on Hess’ law Use of bond energy to calculate energy changes. 4 Thermodynamics Laws of Definition of laws: zeroth, first, thermodynamics second. Calculations in the first law of thermod', 285::int),
    ('J153', 'CHM 003', 'Inorganic Chemistry', 3, 2, 3, NULL::text[], 'At the end of this course, candidates should be able to:
289
1. describe the trends in the physical and chemical properties of elements and their compounds in Period II and III.
2. discuss the gradation in properties across the period from metals through metalloids to nonmetals;
3. describe the general trends in physical and chemical properties of s-, p-, and d-block elements;
4. explain the concept of transition elements in terms of d-block elements.
5. describe the tendency of transition metals to exhibit variable oxidation states and write their electronic configurations.
6. use Valence Bond Theory to explain the properties of coordination compounds.
7. describe how certain gases impact the chemistry of the environment and
8. understand basic concepts in nanomaterials dimensions and applications. Course content S/N Topic Sub-Topic Details & Notes
1. Periodicity General Trends in General trends in physical and Properties chemical properties of period III elements and their compounds (chlorides, oxides, and hydrides). Diagonal relationship between elements in periods II and III. Anomalous behaviour of period II elements. Solid structure of the Definition and types, e.g., face elements centered, body centered and hexagonal closed packing. Structure-properties relationship.
2. Chemistry of Hydrogen Occurrence, isotopes, preparation, Hydrogen physical and chemical properties, and their hydrides.
3. s-block elements Group 1 Physical and chemical properties, extraction of group 1 metals, e.g., Sodium. Trends in properties of their compounds (chlorides, oxides, hydrides, carbonates, hydroxides, 290 nitrates, and sulphates). Uses of group 1 metals. Group 2 Physical and chemical properties, extraction of group 2 metals, e.g., Calcium. Trends in properties of their compounds (chlorides, oxides, hydrides, carbonates, hydroxides, nitrates, and sulphates). Uses of group 2 metals. 4 p-block elements Boron and Physical and Chemical properties, Aluminium Anomalous behavior of Boron, formation of Boranes and Boron hydrides, Amphoteric nature of Aluminum (Reaction with Acids and Bases), Inert pair effect (Stability of +3 and +1 oxidation states), Aluminum alloys and their uses, Uses of group 13 elements. Group 14 Occurrence, allotropic forms of carbon (diamond, amorphous carbon, and fullerene) and tin. Trends in physical and chemical properties of the elements, oxides, hydrides, and halides. Uses of group 14 elements. Group 15 Occurrence, allotropic forms. Trends in physical and chemical properties of the elements, oxides, hydrides, and halides. Uses of group 15 elements. Group 16 Occurrence, allotropic forms. Types of', 289::int),
    ('J153', 'CHM 004', 'Organic Chemistry', 4, 2, 3, NULL::text[], 'At the end of this course, candidates should be able to:
1. discuss the importance of organic compounds and their applications
2. interpret and apply the nomenclature and general formulae of alkanes, alkenes, alkynes, aldehydes, ketones, alcohols, alkyl halides, carboxylic acids, and their derivatives;
3. describe the synthetic routes to simple organic compounds and the simple organic mechanisms of reactions characteristic of these classes of compounds;
4. identify the monomer units present in a given section of a polymer molecule.
5. relate fundamental chemical principles to selected industrial processes;
6. explain the various types of isomerism exhibited by organic compounds; and
7. understand the constituents of crude oil and some basic refining processes. Course content S/N Topic Sub-Topic Details & Notes
1. Development and Sources of organic Tetravalency, Catenation, multiple Importance of compounds, the unique hybridization states and geometries, Organic Chemistry nature of carbon stable multiple bonds. Mention application in the pharmaceutical, petrochemical, and fuel industries, etc.
2. Separation and Separation Techniques Distillation, liquid extraction, Purification sublimation, recrystallization, and Techniques melting point. Chromatography (TLC and Paper chromatography) Structural determination Sodium fusion test, functional of organic compounds groups. using qualitative and Determination of empirical formula quantitative analysis. and molecular formula.
3. Structure and Hybridization Tetravalency and hybridization of Bonding in carbon. Sigma and pi bond formation. 293 Organic Classes and Nomenclature Homologous series, Functional Compounds of Organic Compounds groups, Naming of organic compounds (IUPAC): alkanes, alkenes, alkynes, aldehydes, ketones, alcohols, alkyl halides, arenes, carboxylic acids (and derivatives), amines, and amides.
4. Organic Reactions Covalent Bond Cleavage Homolytic and heterolytic fission, free radicals, Nucleophiles and electrophiles. Mechanism of Reactions Addition, Substitution, and Elimination reactions. Radical reaction. Differences between SN1 and SN2 SE1 and SE2. Electronic Concepts in Inductive, steric, mesomeric, and Organic Chemistry electromeric effects.
5. Stereochemistry Isomerism in Organic Constitutional; chain, position, Compounds metamerism, and functional group isomerism. Tautomerism. Stereoisomerism; geometrical (Cis/ Trans, E/Z) and optical isomerism (chirality and optical activity).
6. Organic Alkanes, Alkenes, and Nomenclature, structure, synthesis, Compounds Alkynes properties, and reactions (for alkene include Markovnikov and Saytzeff’s rules). Alcohols Nomenclature, classes, and structure. Synthesis, properties, and reactions. Distinguishing tests for alcohols (Lucas and Jones reagents). Alkyl halides Nomenclature, structure, synthesis, properties, and reactions. 294 Carbonyl Compounds Nomenclature, structure, synthesis, properties, and reactions (including reduction, reaction with HCN, NaCN, reaction with aqueous I2). Tests for aldehydes and ketones. Carboxylic acids and their Nomenclature, properties. derivatives (treat each Preparation and reactions. separately). Amines and Nitriles Nomenclature and classification of amines and nitriles. Preparation of primary alkylamines. Basicity of amines in terms of their structure. Reactions of amines (formation of diazonium salt) Ethers Nomenclature, properties. Preparation and reactions. Aromatic compounds Kekule structures. Aromaticity. Reactions of benzene (Nitration, sulphonation, halogenation, Friedel-Crafts). Nomenclature of benzene derivatives (mono and di-substituted). Effects of substituents on the reaction of benzene (o, m, p-directors).
7. Macromolecules Carbohydrates Classes of carbohydrates: sugar, (Open chain structures starch, and cellulose. Simple tests only) Proteins Amino acids. Reactions of amino acids (formation of peptide bonds, zwitterions). Classification of peptides. Types of proteins. 295 Polymers Types of polymerization reactions and their differences. Simple structures of polymers. Uses of common polymers. Differences between thermosets and thermoplastics.
8. Petroleum Industry Petrochemicals Constituents of crude oil, refining, and cracking. Chemicals derived from crude oil. CHM 004 Practical
1. Reactions of simple functional groups: Simple organic tests, solubility, sodium fusion test, functional group identification (with emphasis on ketones, aldehydes, and carboxylic acids, alcohols, amines, esters, and ethers).
2. Re-crystallisation and determination of the melting point of organic compounds. RECOMMENDED TEXT
1. Wong, Y. C., Wong, C. T., Onyiruka, S. O. & Akpanisi, L. E. S. (2002). University General Chemistry, Inorganic and Physical. Africana – FEP Publishers Ltd.
2. Ebbing, D., Ragsdale, R. O., & Gammon, S. D. (2005). Essentials of General Chemistry (2nd Ed). Boston M: Houghton Mifflin College Div.
3. Tan, J. & Chan, K. S. (2009). Understanding Advanced Physical Inorganic Chemistry. World Scientific.
4. Madam, R. L. & Tuli, G. D. (2010). Inorganic Chemistry for Universities (Revised Ed.) New Delhi, India: S. Chand.
5. Silberberg, M. S. (2010). Principles of General Chemistry (Second Edition), New York: McGraw-Hill.
6. Osuntogun, O. B., Familoni, O. B. & Alo, B. I. (2012). Basic Organic Chemistry (Third Edition). Lagos: University of Lagos Press.
7. Canhan, G. R. & Overton, T. (2013). Descriptive Inorganic Chemistry. New York: W. H. Freeman and Co 296
8. Cann, P. & Hughes, P. (2015). Cambridge International As and A level Chemistry. United Kingdom: Cambridge University Press.
9. Ajileye, O. O., Amucha, H.O., Mbonu, J. I. & Adams, L. A. (2025). Comprehensive Advanced Level Chemistry for JUPEB, IJMB, Cambridge, and University Examinations. (Revised Ed.). 297 SYLLABUS FOR SCI - J154 MATHEMATICS 298 SYLLABUS FOR SCI - J154 MATHEMATICS GENERAL OBJECTIVES:
The general objectives of this course are to:
1. develop logical thinking, abstract reasoning, and precision in mathematical problem solving;
2. sharpens students’ ability to apply mathematical skills to solve real-life problems in business, engineering, and sciences;
3. equip students to solve mathematical problems creatively, and communicate their solutions effectively; and
4. establish a solid foundation in Mathematics to support students’ future academic and professional endeavours. FIRST SEMESTER COURSES MAT 001: ADVANCED PURE MATHEMATICS (3 UNITS) MAT 002: CALCULUS (3 UNITS) SECOND SEMESTER COURSES MAT 003: STATISTICS (3 UNITS) *MAT 004A: APPLIED MATHEMATICS (3 UNITS) *MAT 004B: APPLIED BUSINESS MATHEMATICS (3 UNITS) *NOTE All Candidates taking Mathematics shall be required to answer questions from MAT 001, 002 and 003 while MAT 004 is in two parts of which candidate will be required to choose one of the parts. For MAT 004, candidates will be required to take ONLY ONE of either MAT 004A (APPLIED MATHEMATICS), or MAT 004B (APPLIED BUSINESS MATHEMATICS). 299 Candidates interested in degree courses in Sciences, Engineering and Environmental Sciences shall be required to take MAT 004A while candidates interested in studying courses in Management Sciences and Social Sciences are required to take MAT 004B. COURSE DESCRIPTION MAT 001: ADVANCED PURE MATHEMATICS Specific Objectives At the end of this course, candidates should be able to:
1. identify and perform operations with number systems, sequences, and series;
2. solve problems involving sets in all their various forms;
3. apply trigonometric identities and concepts to solve mathematical problems; and
4. establish and analyse the relationships between real and complex numbers.', 293::int),
    ('J154', 'MAT 001', 'Advanced Pure Mathematics', 1, 1, 3, NULL::text[], 'At the end of this course, candidates should be able to:
1. identify and perform operations with number systems, sequences, and series;
2. solve problems involving sets in all their various forms;
3. apply trigonometric identities and concepts to solve mathematical problems; and
4. establish and analyse the relationships between real and complex numbers.', 300::int),
    ('J154', 'MAT 002', 'Calculus', 2, 1, 3, NULL::text[], 'At the end of this course, candidates should be able to:
1. identify various functions;
2. evaluate the Limits of functions;
3. obtain derivatives and anti-derivatives of various functions;
4. apply techniques of differentiation and integration to solve practical problems; and
5. formulate and solve simple problems involving first order differential equations.', 302::int),
    ('J154', 'MAT 003', 'Statistics', 3, 2, 3, NULL::text[], 'At the end of this course, candidates should be able to:
1. explain concepts of descriptive statistics
2. analyze data sets using descriptive measures, and graphical representations;
3. solve problems using probability theory;
4. classify random variables, evaluate Probability Mass Functions (PMF), Probability Density Functions (PDF) and Cumulative Distribution Functions (CDF);
5. apply the Normal and Student’s t distributions in hypothesis testing; and
6. solve problems involving regression and correlation analysis.', 304::int),
    ('J154', 'MAT 004A', 'Applied Mathematics', 4, 2, 3, ARRAY['Science', 'Engineering']::text[], 'At the end of this course, candidates should be able to:
1. identify points in a plane base on their coordinates, and establish the relationships between them
2. identify various kinds of conic sections, and solve related problems;
3. evaluate and perform operations on vectors;
4. state and apply Newton’s laws of motion to solve problems;
5. interpret and solve problems involving a particle on an inclined plane; and
6. solve problems related to forces in equilibrium.', 306::int),
    ('J154', 'MAT 004B', 'Applied Business Mathematics', 5, 2, 3, ARRAY['Arts', 'Law', 'Social Sciences', 'Management Sciences', 'Other']::text[], 'candidates should be able to:
1. demonstrate the application of mathematics in business;
2. define and explain basic terms and concepts in business and finance
3. investigate and discuss various options in financial decision-making; and
4. provides solutions to practical problems in business and finance using appropriate mathematical concepts.', 308::int),
    ('J155', 'PHY 001', 'Mechanics and Properties of Matter', 1, 1, 3, NULL::text[], 'At the end of this course, candidates should be able to:
i. differentiate between fundamental and derived physical quantities; ii. apply the concept of dimensional analysis to solve physical problems; 313 iii. define and explain various physical laws related to mechanics and apply them in solving problems using appropriate principles and theories; iv. describe and explain physical phenomena associated with fluid mechanics; and v. acquire and demonstrate basic experimental techniques for carrying out investigations in mechanics.', 313::int),
    ('J155', 'PHY 002', 'Heat, Waves and Optics', 2, 1, 3, NULL::text[], 'At the end of this course, candidates should be able to:
i. explain the concepts of ideal gas, heat, temperature, and the various modes of heat transfer; ii. explain light as an electromagnetic phenomenon and identify the components of the electromagnetic spectrum; iii. determine, both graphically and mathematically, the positions of images formed by mirrors and lenses; iv. explain the dual nature of light—its particle and wave properties as well as the principles governing sound propagation; and v. apply the basic concepts of heat, optics, and sound waves in performing and interpreting related laboratory experiments. 317', 317::int),
    ('J155', 'PHY 003', 'Electricity and Magnetism', 3, 2, 3, NULL::text[], 'At the end of this course, candidates should be able to:
i. state and explain the fundamental laws governing electricity and magnetism; ii. describe the relationship between electrostatic force and the electric field; iii. explain the interaction between electric and magnetic fields; iv. apply relevant laws, principles, and theories to solve problems in electricity and magnetism; and 320 v. identify and describe selected industrial applications of electromagnetic theory.', 320::int),
    ('J155', 'PHY 004', 'Modern Physics', 4, 2, 3, NULL::text[], 'At the end of this course, students should be able to:
i. describe the structure of the atom and its energy spectrum; ii. explain the wave-particle duality of matter and the limitations of classical physics; iii. describe the nature and properties of X-rays; iv. explain the interaction of radiation with matter and solve related problems in modern physics; and v. explain the concept of semiconductors and apply the principles of modern physics to the life sciences and digital technology. 323', 323::int)
  ) AS v(board, code, title, ord, semester, credit, areas, objectives, page)
  JOIN jupeb.board_subject b ON b.code = v.board AND b.syllabus_id = (SELECT id FROM jupeb.syllabus WHERE code = '2027-2031')
ON CONFLICT (subject_id, code) DO UPDATE SET title = EXCLUDED.title, ord = EXCLUDED.ord, semester = EXCLUDED.semester, credit_units = EXCLUDED.credit_units,
    board_subject_id = EXCLUDED.board_subject_id, areas = EXCLUDED.areas, objectives = EXCLUDED.objectives, source_page = EXCLUDED.source_page;

-- the syllabus topics of each course unit, in the order printed (a blank S/N or topic continues the one above)
INSERT INTO jupeb.unit_topic (unit_id, ord, sn, topic, sub_topic, details, source_page)
SELECT u.id, v.ord, v.sn, v.topic, v.sub_topic, v.details, v.page FROM (VALUES
    ('CRS 001', 1, '1', 'Formation and Composition of the Old Testament', 'Inspiration', 'i) Biblical inspiration Explain the term ‘Inspiration’ as it applies to the composition of the Old Testament
ii) Inspirational Theories Discuss the theories such as Dictation Theory, Verbal Plenary, Dynamic or Content Theory, Neo-Orthodox Theory, and Limited Theory', 13::int),
    ('CRS 001', 2, NULL, NULL, 'Canonization', 'i) The meaning of the term ‘Canon’.
ii) process of the canonization of the Old Testament
iii) Explain the different applications of canon with reference to the Old Testament
iv) the criteria for Old Testament canonization.', 13::int),
    ('CRS 001', 3, NULL, NULL, 'Genre of Literature', 'i) Explain the term ‘genre’.
ii) List out the different types of literature in the Old Testament: Historical, Poetic, Wisdom, and Prophetic literature', 13::int),
    ('CRS 001', 4, '2', 'Introduction to the Pentateuch', 'The Canonical Books', 'Identification and categorization of canonical books:
i) Torah (Law) The place of the Torah in Jewish Scripture
ii) Nebiim (Prophets), and
iii) Ketubiim (Writings).', 13::int),
    ('CRS 001', 5, '3', 'Mosaic Authorship of the Pentateuch: An Overview', 'Proofs of Mosaic Authorship', 'i) Discuss the arguments for Mosaic authorship.
ii) Instances for Mosaic authorship: Internal and External evidences', 13::int),
    ('CRS 001', 6, NULL, NULL, 'Arguments Against Mosaic Authorship', 'i) Discuss the arguments against Mosaic authorship.
ii) Mention instances against Mosaic authorship: Internal and External evidences', 14::int),
    ('CRS 001', 7, NULL, NULL, 'The Documentary Hypotheses', 'i) Examine the nature and types of the Documentary Hypotheses to include Early Documentary Hypothesis, Fragmentary Hypothesis and Supplementary Hypothesis
ii) The J. E. D. P. documents. The characteristics of J. E. D. P. documents', 14::int),
    ('CRS 001', 8, '4', 'Introduction to Hebrew Grammar', 'Historical Development of Hebrew Grammar', 'The evolution and development of the Hebrew language', 14::int),
    ('CRS 001', 9, NULL, NULL, 'Hebrew Alphabets', 'Identification of Hebrew alphabets, vowel sounds, vowel letters, numerical values, breathing, and Diphthongs.', 14::int),
    ('CRS 001', 10, NULL, NULL, 'Transliteration and Translation', 'i) Selected Text: Genesis 1:1
ii) Selected Vocabularies: Lord, love, king, man, woman, Sabbath, prophet, heaven, law, and spirit.
iii) Discuss the challenges of transliteration and translation of Hebrew manuscripts', 14::int),
    ('CRS 001', 11, '5', 'Israel’s Nationhood', 'God’s Call of Abraham', 'i) Process of God’s call of Abraham (Gen.12:1-7)
ii) Importance of God’s call of Abraham', 14::int),
    ('CRS 001', 12, NULL, NULL, 'Call of Moses', 'i) Moses’ encounter with God in the wilderness (Exodus 3:1-18, 20:1-20)
ii) Significance of the call of Moses', 14::int),
    ('CRS 001', 13, '6', 'The Rise of Monarchy in Israel', 'Historical Settings for the Establishment', 'i) Identify the factors that gave rise to the Monarchy.
ii) Discuss the roles of Eli and Samuel in the institution of monarchy in Israel.', 14::int),
    ('CRS 001', 14, NULL, NULL, 'of the Monarchy (1 Sam. 1 - 7)', NULL, 15::int),
    ('CRS 001', 15, NULL, NULL, 'The Establishment of the Monarchy (1 Sam. 8-12)', 'i) The ministry of Eli and the birth of Samuel.
ii) The call of Samuel.
iii) The role of Eli and Samuel in the constitution of the monarchy in Israel
iv) The war with the Philistines and the capture of the Ark of God.
v) The role of Samuel as Priest, Judge, and Prophet prior to the monarchy in Israel.', 15::int),
    ('CRS 001', 16, NULL, NULL, 'Factors that led to the request for a king', 'i) Fear of the Philistine, corruption of Samuel’s sons, influence of other nations, Samuel’s old age, and the need for a united living.
ii) How Samuel anointed Saul as king. The inauguration of Saul as king at Gilgal.', 15::int),
    ('CRS 001', 17, NULL, NULL, 'Saul’s Reign and Failures (1 Sam. 13-15)', 'i) Highlight the successes of the reign of King Saul: built the army, formed Israel’s enemy, captured lost land, set up a monarchical structure, etc.
ii) Examine the factors that caused the fall of King Saul: disobedience, envy, impatience, pride, men pleaser, divination (necromancy), influence of evil spirit, etc.', 15::int),
    ('CRS 001', 18, NULL, NULL, 'David’s Reign over Israel (1Sam. 16 -2Sam. 24)', 'i) The anointing of David as king
ii) The achievement of King David: United the kingdom, wrote the Psalms, organised worship, won battles, provided materials for the building of the Temple, killed Goliath, defended the nation, expanded Israel’s territory, etc.
iii) the weaknesses of David: adultery, inability to control his children, murder, family crises, etc.', 15::int),
    ('CRS 001', 19, NULL, NULL, 'The Reign of King Solomon (1 Kg. 1:11-31)', 'i) Solomon’s ascension to the throne.
ii) Appraise his reign and state his contributions to Israel e.g. his building projects,
iii) Explain the folly of King Solomon: forced labour, mixed marriages, many women that drew his heart away from Yahweh, idolatry, etc.', 16::int),
    ('CRS 001', 20, '7', 'The Rise of Prophecy in Israel.', 'Early Manifestations of Prophecy in Israel', 'i) Identify the rise of the Pre-Canonical Prophets in the development of Israel such as Moses, Joshua, Samuel (Jos. 23:1-13)
ii) Examine the characteristics of prophecies:
Inspiration, repentance, dedication to God, fearless, etc.
iii) the role of the prophets: pious worship; school of prophets; etc.', 16::int),
    ('CRS 001', 21, NULL, NULL, 'The Major and Minor Prophets: Themes from Isaiah, Amos and Hosea', 'i) Distinguish between the major and the minor prophets.
ii) Examine Prophet Isaiah’s message on holiness and discuss its relevance to nation-building. (Isa. 1 – 6).
iii) Explain Hosea’s message on love and its implications for Israel (Hos. 1 – 3).
iv) Explain the message of Amos on justice and discuss its relevance to nation building (Amos 1 – 5).
v) Relevance of these messages to nation building (i.e. holiness and nation building, love and nation building, justice and nation building).', 16::int),
    ('CRS 002', 1, '1', 'Historical Background to the New Testament', 'An Overview of the Socio-Political Background of Israel', 'i) Trace the development of the nation of Israel under the Roman Empire.
ii) The Revolt (Maccabean Revolt)
iii) Socio-political groups: Zealot, Herodian, etc.', 17::int),
    ('CRS 002', 2, NULL, NULL, 'Religious Background', 'i) Identify the religious groups and institutions, such as the Pharisees, Sadducees, etc
ii) Religious Institutions: Temple, Synagogue, etc.', 17::int),
    ('CRS 002', 3, '2', 'Introduction to Greek Grammar and Syntax', 'Historical Development of Greek Alphabets', 'i) Discuss the historical evolution of the Greek language
ii) Identification of Greek alphabets (vowels and consonants, Capital and small letters), breathing, and Diphthongs.', 17::int),
    ('CRS 002', 4, NULL, NULL, 'Translation and Transliteration', 'i) Selected Text John 1:1
ii) Selected vocabularies: Love, word, Christ, salvation, grace, fellowship, Church, advocate, repentance, and servant.
iii) Challenges of transliteration and translation of Greek manuscripts.', 18::int),
    ('CRS 002', 5, '3', 'The Synopsis, Materials and the Canonisation of the New Testament', 'The Synopsis and the Materials', 'i) Identify factors that delayed the writing of the Gospels such as persecution, Parousia, the availability of eye-witnesses, etc.
ii) Factors that prompted the writing of the Gospels: death of the eye witnesses; liturgical need; etc.
iii) Highlight the sources of the materials of the Gospel writers: oral and written traditions.', 18::int),
    ('CRS 002', 6, NULL, NULL, 'Canonization of the New Testament', 'i) Meaning of ‘canonization’.
ii) Discuss the process of canonization of the New Testament.', 18::int),
    ('CRS 002', 7, '4', 'The Synoptic Gospels', 'The Synoptic Gospels', 'i) Meaning of ‘Synoptic’: sun – opsis (to view from the same angle).
ii) Mention the Synoptic Gospels:
Matthew, Mark, and Luke
iii) Authorship of the Synoptics.', 18::int),
    ('CRS 002', 8, NULL, NULL, 'The Synoptic Problem/solutions', 'i) The recognition of common materials in the Gospel.
ii) The realization of the special/peculiar sources contained in the Gospels.
iii) The documentary hypothesis.
iv) Reasons for special sources.', 18::int),
    ('CRS 002', 9, '5', 'Modern Criticism of the Gospels', 'Various Criticisms of the Gospels', 'i) Discuss each of the modern criticisms of the gospels: Textual Criticism, Form Criticism, Source Criticism, and Redaction Criticism
ii) Evaluate the effects of each criticism on the Gospels', 18::int),
    ('CRS 002', 10, '6', 'Introduction to the Gospels', 'The Four Gospels', 'i) The aims and objectives of the Four books of the New Testament – a. Matthew b. Mark, c. Luke, and d. John as centred on the activities of the Lord Jesus Christ.
ii) Sources of the Gospels.
iii) Characteristics of each of the Gospels', 19::int),
    ('CRS 002', 11, '7', 'Selected Pastoral and Pauline Epistles', NULL, 'i) Evidence of Paul’s writings before the Gospels were written.
ii) Paul’s conversation and the main contents of his letters; and
iii) The contents of the Epistles - their universality and general outlook
iv) Selected books are: Romans, Galatians, Timothy & Titus', 19::int),
    ('CRS 003', 1, '1', 'An Over-view of Previous Attempts at Christianizing Africa', 'First Attempt - North Africa', 'i) Narrate Pre-Christian contacts with Africa: Abraham, Joseph, etc. were in Egypt, Africa (Gen. 12:10; 39-50).
ii) Discuss Christian contacts with Africa: Baby Jesus, Pentecost Day, Ethiopian Eunuch, etc. (Matt. 2:13-15; Acts. 2; 8:26-40).
iii) Reasons for the failure of planting Christianity during the first attempt:
Heretical teachings/disunity, migration, Islamisation, etc.', 20::int),
    ('CRS 003', 2, NULL, NULL, 'The Second Attempt – the Portuguese Efforts', 'i) Narrate how Prince Henry of Portugal sponsored numerous expeditions to Africa from 1418 to 1460.
ii) Evaluate the reasons for the explorations of Africa: Evangelical, commercial, etc.
iii) State the reasons for their failure of planting Christianity: slavery/slave trade, climate, paucity of funds, etc.', 20::int),
    ('CRS 003', 3, '2', 'Establishment of Christianity in Sierra Leone', 'The Evangelical Revivals in Europe and America', 'i) Effects of the evangelical revivals:
Birth of Mission Societies - BMS, CMS, LMS; Emphasis on faith, zeal, and philanthropy; etc.
ii) List and explain the Anti-Slavery movements: The Abolitionists, Role of the Freed Slaves, etc.', 20::int),
    ('CRS 003', 4, NULL, NULL, 'The Founding of Sierra Leone and the Planting of Christianity.', 'i) Give reasons for founding Sierra Leone: Economic, Social, Religious, etc.
ii) What are the successes and failures of the 1841, 1845, and 1857 Niger expeditions.', 21::int),
    ('CRS 003', 5, '3', 'The Planting of Christianity in Nigeria', 'Missionary Activities in Yoruba Land', 'i) Narrate how Christianity was introduced in Abeokuta, Ibadan, Lagos, etc.
ii) What are the influences of missionary activities, e.g. CMS, RCM, WMS, Baptist, etc.', 21::int),
    ('CRS 003', 6, NULL, NULL, 'Missionary activities in Igbo Land', 'i) Appraise the introduction of Christianity in Onitsha, Aba, etc.
ii) Assess the influence of the missionary activities of the CMS, RCM- Holy Ghost Fathers, Methodist, etc.', 21::int),
    ('CRS 003', 7, NULL, NULL, 'Missionary Activities in Northern Nigeria.', 'i) Discuss the introduction of Christianity in Lokoja, Zaria, Benue, etc.
ii) Analyse the influence of the missionary activities of the CMS, RCM, SUM, SIM, etc.', 21::int),
    ('CRS 003', 8, NULL, NULL, 'Missionary Activities in Calabar and Bonny Areas.', 'i) Appraise the introduction of Christianity in Calabar, Uyo, Oron, Bonny, and other parts of Nigeria through the efforts of the missionaries.', 21::int),
    ('CRS 003', 9, NULL, NULL, NULL, 'ii) State the influence of the missionary activities of the CMS, Presbyterian, Methodist, Qua Iboe Mission QIM, etc.', 22::int),
    ('CRS 003', 10, '4', 'The Rise of the African Independent Churches (AICs)', 'Clarification and Classification of the African Independent Churches (AICs)', 'i) Clarification of African Independent/Indigenous/Initiated Churches (AICs).
ii) Classification of the AICs.
iii) Distinguish the AICs from the Mainline and Pentecostal Churches.
iv) Characteristics of the AICs: White garment, use of prayer aids, emphasis on spirituality, proliferation, etc.
v) Some founder/leaders: Garrick S. Braide, Moses Orimolade, S.B.J. Oschoffa, Sophie Odunlami Ajayi, and Joseph Ayo Babalola', 22::int),
    ('CRS 003', 11, '5', 'Pentecostalism in Nigeria', 'History and Development of Pentecostal Churches in Nigeria', 'i) Define Pentecostalism
ii) Name some features of Pentecostalism: women ordination, media evangelism, prosperity gospel, etc.
iii) Some Founders/Leaders: Bishop Benson Idahosa, W. F. Kumuyi, Apostle Numbere, Mike Okonkwo, David Oyedepo, Lazarus Muoka, and Enoch Adeboye.', 22::int),
    ('CRS 003', 12, '6', 'Proliferation of Churches in Nigeria', 'Clarification of Term and Causes of Proliferation', 'i) Clarify the term ‘Proliferation.’
ii) Enumerate the causes of Proliferation of Churches:
Leadership tussle, unemployment, doctrinal disagreements, etc.', 22::int),
    ('CRS 003', 13, NULL, NULL, 'Impacts of Proliferation of Churches', 'i) State the merits of Proliferation of Churches: Expansion of the Church, employment generation, etc.
ii) Evaluate the impact of Proliferation of Churches: Unhealthy rivalry, heresy, abuses, etc.', 23::int),
    ('CRS 003', 14, '7', 'Christian Associations in Nigeria', 'The rise, growth and impact of Christian Organisations in Nigeria.', 'Discuss the history, impact, challenges, merits and demerits of:
i) Christian Association of Nigeria (CAN),
ii) The Catholic Secretariat of Nigeria (CSN),
iii) Pentecostal Fellowship of Nigeria (PFN),
iv) Christian Council of Nigeria (CCN),
v) Organisation of African Instituted Churches (OAIC), and
vi) TEKAN/ECWA', 23::int),
    ('CRS 004', 1, '1', 'Relationship between Religion and Society', 'Meaning of Religion and Society', 'i) Define the terms ‘Religion’ and ‘Society’
ii) Critically assess the dimensions of ‘Christian’ religion: material/symbols, rituals, experience, ethics, myths, doctrine, and socials/institutions', 24::int),
    ('CRS 004', 2, NULL, NULL, 'Definition of Religion by scholars', 'i) Selected Scholars: Karl Marx, Rudolph Otto, Emmanuel Kant, Sigmund Freud, Emile Durkheim, Edward Burnett Tylor, James G. Frazer, Friedrich Schleiermacher, and William T. Hall
ii) Critique each definition from the Nigerian context', 24::int),
    ('CRS 004', 3, NULL, NULL, 'Relationship between Religion and Society.', 'Discuss how Religion and Society relate.', 24::int),
    ('CRS 004', 4, '2', 'Theories of Religion', 'Conflict Theory: Karl Marx', 'i) Meaning, Background, Contextual basis of the theory
ii) Evaluate the significance of the theory on Nigerian society', 24::int),
    ('CRS 004', 5, NULL, NULL, 'Functional Theory: Emile Durkheim', 'i) Meaning, Background, Contextual basis of the theory
ii) Evaluate the significance of the theory on Nigerian society', 24::int),
    ('CRS 004', 6, NULL, NULL, 'Social Change Theory: Max Weber', 'i) Meaning, Background, Contextual basis of the theory
ii) Evaluate the significance of the theory on Nigerian society', 24::int),
    ('CRS 004', 7, NULL, NULL, 'Psychoanalytical Theory: Sigmund Freud', 'i) Meaning, Background, Contextual basis of the theory
ii) Evaluate the significance of the theory on Nigerian society', 24::int),
    ('CRS 004', 8, NULL, NULL, 'Phenomenological Theory: Friedrich Schleiermacher', 'i) Meaning, Background, Contextual basis of the theory
ii) Evaluate the significance of the theory on Nigerian society', 25::int),
    ('CRS 004', 9, NULL, NULL, 'Social Theory: Immanuel Kant', 'i) Meaning, Background, Contextual basis of the theory
ii) Evaluate the significance of the theory on Nigerian society', 25::int),
    ('CRS 004', 10, '3', 'Measures of Religiosity', 'Clarification of Terms', 'Clarify the terms ‘measure of religiosity.’', 25::int),
    ('CRS 004', 11, NULL, NULL, 'Criteria for Measuring Religiosity', 'Identify the criteria for measuring religiosity: prayer, church attendance, financial responsibility, use of religious language, etc.', 25::int),
    ('CRS 004', 12, '4', 'Functions of religion', 'General Functions', 'i) Functions of religion in the society: maintenance of law and order; social cohesion; social control; etc.
ii) Distinguish between positive and negative functions of religion', 25::int),
    ('CRS 004', 13, '5', 'Religion, Peace, and Conflict Resolution', 'Religion and Peace in the Society', 'i) religion and peace in the society
ii) How religion can enhance peace in the society, inter-religious dialogue, tolerance, inter/intra-religious activities, etc.', 25::int),
    ('CRS 004', 14, NULL, NULL, 'Religion and Conflict Resolution', 'Relate how religion can be used as a tool for conflict resolution:
Dialogue, Forgiveness, Teaching/Preaching, Tolerance, Patience, Contentment, Counselling, Reconciliation, etc.', 25::int),
    ('CRS 004', 15, '6', 'Religious Personality and Human Values', 'Religious Personality', 'Clarify the term ‘Religious Personality.’', 26::int),
    ('CRS 004', 16, NULL, NULL, 'Human Values', 'Identification of some human values: love, peace, benevolence, respect, responsibility, contentment, loyalty, hard work, honesty, power, dignity, perseverance, self-control, candour, security, etc.', 26::int),
    ('CRS 004', 17, NULL, NULL, 'Relating Religious Personality to Human values', 'State how religious personality can promote human values such as religious codes, sermons/teachings, promotion, reward motive, etc.', 26::int),
    ('CRS 004', 18, '7', 'Christian Response to Contemporary Issues', 'Christianity and Contemporary issues in the Nigerian Society.', 'Mention some contemporary Issues such as Drug Abuse, Cultism, Corruption, Insurgencies (e.g. Terrorism, Banditry), Rape, Abortion, Euthanasia, Examination Malpractices, Epidemic Diseases (e.g. Covid 19, HIV/AIDS), Bad Governance, Fundamentalism, Protest, Ritual Killings, Syncretism, Gambling, Kidnapping, Fraud/Cyber Crime, Exploitation, Homosexuality (LGBTQ+), Human Trafficking, Electoral Violence, and Gender Based Violence, migration (i.e. Japa & Japada syndrome), & Artificial Intelligence.', 26::int),
    ('CRS 004', 19, '4', 'Adam Augustyn et al {Eds.} (2020). Bible. Encyclopedia Britannica.', NULL, '| | | Retrieved', 27::int),
    ('CRS 004', 20, '22 April 2021 from', NULL, NULL, 'https://www.britannica.com/topic/Bible | | |', 27::int),
    ('CRS 004', 21, '5. Carvalho, C. L. {Ed.} (2014). Anselm companion to the Bible: With NSRV', NULL, NULL, '| | |', 27::int),
    ('CRS 004', 22, 'translation', NULL, 'Winona, Minnesota : Anselm Academic', '| | |', 27::int),
    ('FRE 001', 1, 'A', 'Oral French & Phonetics I', NULL, NULL, 31::int),
    ('FRE 001', 2, '1', 'Saluer', '- Salutations de tous les moments de la journée - Prononciation des sons', 'The course aims at teaching the candidates how to pronounce French words correctly. Topics to be studied include: French alphabets, sounds Pronunciations (rhythm, linking of sounds). Oral comprehension shall be enhanced through the use of audio and video tapes.', 31::int),
    ('FRE 001', 3, '2', 'Se présenter et présenter quelqu’un', '- Se présenter et présenter quelqu’un comme : ➢ Moi-même ➢ Mon meilleur ami ➢ Mon père ➢ Ma mère ➢ Mon oncle, etc. - Les nationalités - Parler de loisir et des goûts', 'Candidates should be able to introduce:
• themselves
• their friends
• classmates and
• family members This also includes how to express likes and dislikes, or description of people, places, and objects, using simple affirmative and negative sentences.', 31::int),
    ('FRE 001', 4, '3', 'Demander et répondre aux questions en classe.', '- Les pronoms interrogatifs : qui, quoi, quand, ou, quel(le), est-ce que, etc. - Inversion de sujet : es-tu, est-il/elle ? etc.', 'Candidates should be able to use ‘wh’ questions to give and respond to classroom commands, talk about their feelings, opinions and ideas in a simple sentence.', 31::int),
    ('FRE 001', 5, NULL, NULL, '- Expressions sur les activités en classe ex : asseyez-vous, venez ici, levez-vous, ouvrez vos livres, fermez vos livres, écoutez, répétez, écrivez, répondez etc…', NULL, 32::int),
    ('FRE 001', 6, '4', 'Identifier des choses et des personnes', '- Identification des objets (qu’est-ce que c’est? etc.) - Identification des personnes selon leurs professions (qui est-ce? Qu’est-ce qu’il/elle fait ? etc.)', 'Candidates should be able to identify objects in the classroom and the immediate environment. They will also be able to identify people and their various professions.', 32::int),
    ('FRE 001', 7, '5', 'Savoir compter', 'Les nombres - Les nombres cardinaux - Les nombres ordinaux - Le calendrier', 'Candidates should be able to tell the date, talk about the days of the week, the months of the year, and also be able to say the price of goods and services.', 32::int),
    ('FRE 001', 8, '6', 'Demander et dire l’heure', '- Les expressions liées à l’heure : Quelle heure est-il ? Il est… - Les vocabulaires liés à l’heure : minute, quart, demie, moins, et, pile, etc. - Les moments de la journée et les repas correspondants.', 'Candidates should be able to situate themselves within the different times of the day and also be able to talk about their daily routines.', 32::int),
    ('FRE 001', 9, '7', 'Se déplacer', '- Les endroits et les lieux (le bureau, le', 'Candidates should able to talk about places in town,', 32::int),
    ('FRE 001', 10, NULL, NULL, 'marché, le stade, l’église, la mosquée, etc. - Les moyens de transport : le vélo, la voiture, le train, le bateau, l’avion, etc. - Les vocabulaires liés au déplacement : tourner à gauche/ à droite, aller tout droit, etc.', 'around the school and the various means of transportation.', 33::int),
    ('FRE 001', 11, '8', 'Inviter quelqu’un Accepter et refuser une invitation', '- Vouvoiement : forme formelle - Tutoiement : forme informelle - Expressions liées à l’acceptation : avec plaisir, volontiers, être content, etc. - Expressions liées au refus : être désolé, s’excuser de, regretter de, etc.', 'Candidates should able to accept invitation or extend formal or informal invitation to friends, colleagues, and family members on different occasions.', 33::int),
    ('FRE 001', 12, 'B', 'Basic French Grammar I', NULL, NULL, 33::int),
    ('FRE 001', 13, '9', 'Les verbes au présent de l’indicatif', '- Les pronoms personnels - Les verbes du 1er groupe - Les verbes du 2e groupe - Les verbes irréguliers - Aimer + nom, - Aimer + infinitif', 'Candidates should able to express themselves using auxiliary and basic verbs appropriately. They should be able to combine the verb ‘aimer’ + noun or ‘aimer + infinitive of other verbs.', 33::int),
    ('FRE 001', 14, '10', 'Les verbes aux temps passés de l’indicatif', '- L’imparfait - Le passé composé - L’auxiliaire être et avoir', 'Candidates should able to form simple sentences using imperfect and past tenses when narrating past events and activities. Emphasis should be laid on the mastery of the use of: ‘être’ & ‘avoir’ as auxiliaries when conjugating verbs in the ‘passé composé’.', 34::int),
    ('FRE 001', 15, '11', 'Les verbes aux temps du futur', '- Le futur proche - Le futur simple - Le conditionnel', 'Candidates should able to form simple sentences using future or conditional tenses when narrating future events or speaking about personal projects.', 34::int),
    ('FRE 001', 16, '12', 'Les noms et les articles', '- Les articles définis - Les articles indéfinis - Les articles partitifs - Le genre des noms - Les noms communs - Les noms propres - La pluralisation - L’accord', 'Candidates should able to group nouns into various types (proper, common, collective nouns, etc.', 34::int),
    ('FRE 001', 17, '13', 'Les adjectifs', '- Les adjectifs possessifs - Les adjectifs démonstratifs - Les adjectifs qualificatifs', 'Candidates should able to identify and use different types of adjectives correctly. They should also be able to show their mastery of agreement of adjectives with gender and number of nouns.', 34::int),
    ('FRE 001', 18, '14', 'Les prépositions', '- Les prépositions de lieu (a, dans, sur, etc.) - Les prépositions de direction (Vers, a, de, etc.) - L’emploi des prépositions dans les phrases (Aller a la piscine, au marché, parler de soi même, etc.', 'Candidates should able to identify and use various prepositions correctly in simple sentences. They should also be able to use common preposition in diverse contexts.', 35::int),
    ('FRE 001', 19, '15', 'Les pronoms', '- Les pronoms possessifs (le mien, la mienne, etc.) - Les pronoms démonstratifs (celui, celle, cela, etc.) - Les pronoms interrogatifs (lequel, laquelle, lesquel(le)s, etc.', 'Candidates should able to identify and use different pronouns in simple sentences.', 35::int),
    ('FRE 001', 20, '16', 'La négation', '- Adverbes de négation : (ne…pas, ne…plus, ne…. rien, ne ….. jamais, etc.) - Formation des phrases négatives', 'Candidates should able to identify adverbs used to form negative sentences. Additionally, emphasis will be laid on the sentence order in negative sentences. They will also be required to transform affirmative sentences to negative sentences and vice versa.', 35::int),
    ('FRE 001', 21, '17', 'L’emploi de certains verbes dans des phrases simples', '- 1er groupe (er) + infinitif - 2ème groupe (ir) + infinitif - 3ème groupe (oir, re) + infinitif', 'The verb segment would consider the following examples: Je mange du riz. Je finis vite. Je vois le professeur. Je vais faire mon devoir.', 36::int),
    ('FRE 002', 1, '1', 'Production écrite :', '- Dictée : mots, phrases, expressions, textes simples/ courts', 'The course aims at teaching the candidate how to write simple sentences. The exercise will acquaint the candidate with the correct spellings of words.', 37::int),
    ('FRE 002', 2, '2', 'Description', '- Décrire une personne, (un/une ami(e), membres de la famille, etc. - Décrire une place/ un endroit', 'Candidates should be able to describe:
- people
- and places: themselves
- family, and
- immediate environments (school, market, stadium office, etc).', 37::int),
    ('FRE 002', 3, '3', 'Ecrire une lettre', '- Lettre informelle (amicale) - Lettre officielle', 'Candidates should be able to write short and concise formal and informal letters.', 37::int),
    ('FRE 002', 4, '4', 'Politiques et Organisations Internationales', '- Politique interne : les partis politiques du Nigeria - Les régions géopolitiques - Structure gouvernementale - Politique externe : - Les pays voisins du Nigeria - Les pays francophones d’Afrique et du monde - Les organisations sous-régionales (CEDEAO, AU), etc', 'Candidates should be able to list/identify:
- Nigerian political parties and their structures
- Geo-political regions some West-African sub-regional organisations like:
ECOWAS, AU, etc.
- the francophone countries surrounding Nigeria and other Francophone countries in Africa and in the world', 37::int),
    ('FRE 002', 5, '5', 'Le français dans le monde', '- L’importance du français au Nigeria. - Les variétés du français dans le monde d’aujourd’hui : français standard, français canadien, français ivoirien, français béninois, etc.', 'In addition to their ability to provide basic information on:
- geography
- education
- administration and
- important festivals of France, candidates should be able to state the importance of French in Nigeria and identify its varieties in the world such as Canadian, Standard, Ivorian etc.', 38::int),
    ('FRE 002', 6, '6', 'La politique linguistique dans le système d’éducation en France', '- Objectifs de la politique linguistique éducative en France - Rôle du français dans l’éducation nationale - Politique pour promouvoir le français comme langue d’enseignement en France - L’enseignement des langues régionales et étrangères', 'Candidates should be able to:
- analyse the objectives and implications of language policy in French education
- identify/list the role of French in France’s educational system
- identify/list policies regarding regional and foreign languages in education', 38::int),
    ('FRE 002', 7, '7', 'Les fêtes en France', '- La fête de noël - La fête de nouvel an etc. - La fête de paques - La fête du 14 juillet', 'Candidates should be able to list various festival in French and also identify their periods of celebrations.', 38::int),
    ('FRE 002', 8, '8', 'La vie en France', '- L’habillement - Formule de politesse - La gastronomie - Horaires - Loisirs - Politique, etc.', 'Candidates should be able to:
- identify and name different wears and foods in French
- describe time and places of leisure', 39::int),
    ('FRE 002', 9, '9', 'Introduction à la littérature', '- Définition et importance de la littérature - Thème, personnage et style d’un texte - Analyses des extraits de textes. - Exploration de thèmes littéraires courants', 'Candidates should be able to define literature, identify the three major genres, and also be able to make appraisal of common literary words and texts.', 39::int),
    ('FRE 002', 10, '10', 'Introduction aux genres littéraires', '- Différents genres littéraires (roman, théâtre, et poésie) - Caractéristiques des trois genres principaux de la littérature - Evolution du roman', 'Candidates should be able to state characteristics of poetry, prose or drama, and also be able to identify first and third person narrative techniques within a given text.', 39::int),
    ('FRE 003', 1, 'A', 'Oral French & Phonetics II', NULL, NULL, 40::int),
    ('FRE 003', 2, '1', 'Oral French', '- La lecture - La compréhension orale', 'This is a continuation of FRE
001. The candidates will be required to read and report information gathered from newspapers the electronic media, in French.', 40::int),
    ('FRE 003', 3, '2', 'La phonétique', '- 37 sons phonétiques du français - 18 sons consonantiques - 16 sons vocaliques - 3 semi-consonnes ou semi-voyelles', 'The course also aims at helping the candidates in expressing interest or indifference for something, making a promise, describing an environment, expressing regrets, tastes, reporting a speech, asking for information and responding to questions. The course also teaches how to introduce people by their names and professions as well as how to ask for permission and how to disapprove ideas. Phonetically, the candidate should be able to ddistinguish between occlusives, fricatives (p,b,t,d,k,g) / (f,v,s,z) and nasals, and also be able to link vowel and consonant sounds. Oral or listening comprehension shall be enhanced through the use of audio and video tapes.', 40::int),
    ('FRE 003', 4, '3', 'L’appareil phonatoire', '- Les organes phonatoires (les lèvres, le nez, les dents, la langue etc)', NULL, 40::int),
    ('FRE 003', 5, '4', 'La description des sons phonétiques', '- Lieu d’articulation - Mode d’articulation', NULL, 40::int),
    ('FRE 003', 6, '5', 'La description de l’articulation des sons phonétiques', '- La description des sons vocaliques /a/, /o/, /u/etc. - La description des sons consonantiques /m/, /p/, /t/ etc…', NULL, 40::int),
    ('FRE 003', 7, '6', 'La transcription phonétique', '- La transcription dans la prononciation de quelques mots français.', NULL, 40::int),
    ('FRE 003', 8, 'B', 'Basic French Grammar II', NULL, NULL, 40::int),
    ('FRE 003', 9, '7', 'Les voix actives et passives', '- Les phrases à la forme active - Les phrases à la forme passive', 'This course is designed to cover the following areas: active and passive voices as well as pronominal verb forms. Words', 40::int),
    ('FRE 003', 10, NULL, NULL, '- La voix pronominale', 'for situating events in the context of time: (le lendemain, la veille, hier, plus tard), impersonal expressions, and conjugation of verbs', 41::int),
    ('FRE 003', 11, '8', 'Les verbes pronominaux', '- L’emploi des verbes à la forme pronominale à l’intérieur des phrases', NULL, 41::int),
    ('FRE 003', 12, '9', 'L’emploi des articles définis et indéfinis', '- L’emploi des articles définis à l’intérieur des phrases - L’emploi des articles indéfinis à l’intérieur des phrases', 'In addition to being able to distinguish between definite and indefinite articles, candidates should be able to use definite and indefinite articles with non-specific nouns correctly.', 41::int),
    ('FRE 003', 13, '10', 'La traduction', '- Définition de la traduction - Importance de la traduction - Les différents types de traduction (la traduction littéraire, juridique, scientifique, et.) - La traduction littérale (l’emprunt, le calque et le mot-à-mot)', 'Through exposure to different types of translation, Candidates are expected to translate from English to French and vice versa. They should be able to bridge the gap between English and French by grasping complex structures and enhancing vocabulary acquisition through direct comparison of both languages. Their accuracy in reading and writing will also be improved via translation of simple sentences on themselves, others and their daily routines.', 41::int),
    ('FRE 003', 14, '11', 'Les expressions de certitude et de doute', '- L’emploi des expressions de certitude : (certainement, surement, vivement, etc.) - L’emploi des expressions de doute (peut-être, probablement, il se peut que…, il semble etc.)', 'Candidates should be able express doubts or certainty through the use of appropriate words and simple sentences.', 41::int),
    ('FRE 003', 15, '12', 'Se situer dans le temps', '- Exprimer une situation à travers le temps (hier, aujourd’hui, demain, lendemain, la veille, hier, plus tard etc.) - Les temps verbaux (passé, présent, et futur) - Les expressions temporelles (à, en, ou dans, comme : à 5 heures, en janvier, dans un mois, etc.)', 'Candidates should be able to situate themselves in different time through the use of appropriate verb tenses. They should also be able to express actions and events in different time frames.', 42::int),
    ('FRE 004', 1, '1', 'Production écrite - L (l la - L c - L m e', '- Rediger un texte (narratif, descriptif, et argumentatif) a structure d’un texte ’introduction, le corps du texte, et conclusion) ’emploi de la grammaire en ontexte ’usage des connecteurs et les ots de transition : (cependant, nsuite, donc, etc.)', 'The course progresses from writing short and simple passages to writing more elaborate ones within the frames of descriptive, argumentative and narrative essays of about 10 lines. Candidates should be able to apply grammar rules through effective structuring and organization of simple texts.', 42::int),
    ('FRE 004', 2, '2', 'Type de rédactions', '- La narration (parler d’un evenemnt ) - La description (le portrait d’un ami) - La lettre (formelle/informelle)', 'Candidates should be able to express their ideas and thoughts effectively through writing of short and coherent texts on familiar topics. Dictation exercises to teach correct spelling of words is also necessary. Topics include:
the family, candidate’s immediate environment, writing of narrative, descriptive and argumentative essays, writing of curriculum vitae, different kinds of formal/informal letters, all in elaborate forms.', 43::int),
    ('FRE 004', 3, '3', 'Importance de la langue française', 'Avantages de parler français - Opportunités professionnelles et culturelles - Accès à la culture et la littérature francophone Le français dans un contexte global - Le français comme langue de communication internationale - L’importance du français pour la coopération internationale', 'Candidates should be able to:
- understand the importance of French on the global stage
- identify the benefits and opportunities of speaking French
- understand the role of French in global communication and cooperation.', 43::int),
    ('FRE 004', 4, '4', 'Les francophones', '- Définition et répartition géographique des francophones - Les pays où le français est langue officielle - Culture et traditions dans les pays francophones', 'Candidates should be able to further understand the importance of french in international context via the the francophones. In addition to being able to identify and', 43::int),
    ('FRE 004', 5, '5', 'La littérature négro-africaine d’expression française', '- Origine et évolution de la littérature négro-africaine - Les types de littérature (coloniale, anticoloniale et postcoloniale) - La négritude (les revues, les pionniers et les œuvres majeures', 'Candidates should be exposed to Negro-African French literature, its origins and evolution. This will be followed by stages of Francophone literature and special emphasis will be on the Negritude movement, how it evolved, the pioneers and their major works.', 44::int),
    ('HST 001', 1, '1', 'I ntroduction to History', 'Definitions, Meanings, Sources, Approaches and importance of History', 'Definition and meaning i. History as past human activities ii. History as the study of the past human activities iii. History as dialogue between the past and the present iv. History as evidence-based discipline v. History as skill, art and craft, etc. vi. Historiography: the art and craft of writing history Sources i. Primary Sources e.g. Oral evidence, archival material, Arabic sources, ethnographic data, ii. Secondary Sources e.g. Textbooks, Journal articles, etc. iii. Tertiary Sources e.g Electronic sources, online sources Approaches i. Descriptive ii. Analytical iii. Argumentative iv. Explorative Importance i. Mediating discipline ii. Satisfy curiosity iii. As a career iv. To understand change and continuity v. Preservation of culture and tradition vi. Promotes nation building vii. All knowledge is historical viii. understand the society, etc.', 48::int),
    ('HST 001', 2, '2', 'A rchaeology of Nigeria', 'Definitions, meanings, techniques/methods, significance of archaeology and major archaeological sites in Nigeria.', 'Definitions and Meanings i. Archaeology as the study of the past through the material remains left behind by human beings ii.The study of ancient things iii.It can also study more recent societies as long as material evidence is available. Eg these remains include tools, weapons, houses, graves, art works etc. Techniques/Methods i. Remote sensing ii. Isotope Analysis iii. Artefact curation iv. Geophysics survey v. Surface survey vi. Test pitting vii. Stratigraphic Excavation viii. Radiocarbon Dating ix. Material analysis x. Archaeological Photogrammetry etc. Significance of Archaeology i. Crucial for understanding human history ii. Reveals unknown past iii. Helps scholars to understand how early people hunted, farm, made tools, trading and built communities iv. Preserves cultural heritage, protects endangered sites and artefacts v. Provides evidence of material remains of past generations Major archaeological sites and significance in Nigeria The Nok Culture:
i. Terracotta Sculpture', 49::int),
    ('HST 001', 3, NULL, NULL, NULL, 'ii. Clay Figurines of animals iii. Iron tools iv. Stone Ornaments v. Cylindrical heads vi. Pierced eyes, nose, mouth, and ears etc. The Benin Civilisation:
i. Benin Sculpture ii. religious objects iii. Ceremonial weapons iv. Ivory masks v. Animal heads vi. Figurines vii. Cast bronze viii. Cast ivory ix. Brass casting x. Ancestral altars xi. Careful treatment of hair etc Ife Civilisation:
i. Ife Terracotta ii. Bronze iii. Stones iv. Depiction of leaders with large head to indicate their powers, etc. Igbo-Ukwu Civilisation:
i. Beaded lines ii. Concentric circles iii. Development of bowls iv. Bowls made of ornaments etc.', 50::int),
    ('HST 001', 4, '3', 'H istory of West Africa from 1000 to 1500 AD', 'The rise and fall of ancient Ghana and Mali empires; intergroup relations; the trans-Saharan trade and contact', 'Factors responsible for the emergence of Ancient Ghana Empire:
i. Geographical ii. Political (leadership and military)', 50::int),
    ('HST 001', 5, NULL, NULL, 'with the Arabs; introduction of Christianity and its challenges before 1500 AD', 'iii. Economic (control of trade routes, collection of custom duties and mineral resources like gold and salt); and social. Reasons for the fall of Ancient Ghana Empire:
i. The rise of vassal states ii. Weak military/leadership; among others. i. Sundiata Keita and the emergence of Mali. ii. Mali under Mansa Musa: Islamization of Mali- construction of mosques, pilgrimage to Mecca, introduction of Islamic laws. (The wastage of the natural resources of Mali by Mansa Musa should be related to the behaviour of contemporary African leaders) Reasons for the fall of the Empire:
i. Rise of vassal states ii. Succession dispute iii. Weak military iv. Internal disputes Factors that enhanced intergroup relations i. Trade ii. Trade routes and markets iii. Religious, social and cultural institutions iv. Migration v. Diplomacy vi. War Factor that promoted Trans-Saharan Trade i. Availability of camel ii. The spread of Islam', 51::int),
    ('HST 001', 6, NULL, NULL, NULL, 'iii. The desire for imported foreign goods iv. Advantage of pilgrimage v. Trade routes vi. Economic interdependence Early contacts with the Europeans and coastal communities i. Role of the Portuguese explorers ii. Resistance from Islam iii. Resistance from Traditional beliefs iv. Hostile climate and scarcity of missionaries; v. tropical diseases e.g malaria vi. cultural and Linguistic barriers vii. Methodological Errors viii. Impact of the Slave Trade', 52::int),
    ('HST 001', 7, '4', 'E mpires and Kingdoms in Nigeria', 'Origin, Evolution and Fall of Kanem Bornu Empire, Oyo Empire and Benin Kingdom.', 'i. The reigns of Mai Idris Alooma and Shehu El-Kanemi of Karnem Bornu. Factors that led to the Rise of Oyo i. Constitution of the Empire ii. Military strength iii. Geographical location iv. Economic factor v. Indigenous industries vi. Homogenous culture The Fall of Oyo Empire i. Internal crisis ii. Constitutional crisis iii. Rise of vassals states iv. The impact of the Islamic jihad v. Loss of trade routes vi. The Afonja factors', 52::int),
    ('HST 001', 8, NULL, NULL, NULL, 'vii. The 19th century civil wars, etc The Rise of Benin Kingdom i. Centralized system of administration ii. Collection of tributes from vassal states iii. Geographical factor iv. Economic factor v. External relations with the Yoruba vi. Access to firearms vii. Leadership Factors that led to the fall of the Benin Kingdom i. the British invasion of 1897 ii. decline of economic revenue iii. overconcentration of power in the city iv. weak military v. succession disputes vi. emergence of weak rulers, etc.', 53::int),
    ('HST 001', 9, '5', 'O mani Arabs in East Africa', 'The reign of Sayyid Said', 'i. East African coastland before the rise of the Omani Empire. ii. Sayyid Said and the rise of the Omani Empire.', 53::int),
    ('HST 001', 10, '6', 'T he Bantu Migrations and Settlements', 'Traditions of origin of the migrants, Description of the Bantu migrations and settlements, Reasons for the Bantu migrations, Effects of the Bantu migrations.', 'i. a. The West African tradition of origin of Bantu Migrants b. South Eastern Congo tradition of origin of Bantu Migrants. ii. The four Bantu groups: Inter-lacustrine/western Bantu, central Bantu, highland Bantu, southern Tanzanian Bantu. Reasons for the migrations:
i. Drought and famine ii. Overcrowding/population increase iii. War iv. Internal conflicts v. Epidemic diseases/natural calamities vi. Search for fertile lands vii. Adventure viii. Group influence ix. Need for water and pasture x. Export of iron-working culture. Effects:
i. Introduction and spread of iron-working ii. Introduction of new crops like yam and banana iii. Racial mixture iv. Introduction of central administration v. Building of permanent settlements vi. Emergence of subsistence agriculture vii. Depopulation viii. loss of culture and cultural absorption ix. and transformation of languages.', 54::int),
    ('HST 001', 11, '7', 'T he Rise of Shaka and Mfecane', 'Rise of Shaka, The Mfecane', 'Rise of Shaka:
i. His military/political, social/cultural, economic reforms. ii. Contact with Europeans and expansionist policies. Mfecane:
Nature and consequences', 55::int),
    ('HST 001', 12, '8', 'T he French Occupation of Egypt', 'Factors Responsible for the French Invasion of Egypt, The Impact of French Invasion and Occupation of Egypt, Mohammed Ali and the Modernization of Egypt', 'Factors:
i. Strategic location of Egypt ii. Rivalry between France and Britain iii. Weakness of the Ottoman Empire… Impact:
Modernisation of Egypt, i. Technological advancement, ii. Introduction of French laws Contribution of Muhammed Ali i. Fiscal Reforms ii. Agricultural Reforms iii. Political Reforms iv. Social Reforms v. Economic Reforms vi. Educational Reforms vii. Military Reforms', 55::int),
    ('HST 002', 1, '1', 'Introduction to Human Evolution', 'Definition and concept; importance, process; theories; and formation of racial types', 'Definition and Concepts i. The process by which man, animal, plants and other living organisms are transformed into different forms by the accumulation of changes ii. It refers to genetic change in species or population over time. iii. It is the process that produces abetter or more complex form. Importance of Evolution i. Explain the diversity of life on earth ii. Provide the foundation for modern biology iii. Unifying principles of biology iv. Understanding human origin v. Agriculture and food production etc. Process of Evolution i. Mutation ii. Non-random mating, iii. Gene flow iv. Finite population size (genetic drift) v. Natural selection Theories of Human Evolution i. Natural selection ii. Creationists theory iii. Big bang theory Racial Types i. Black/Negroid ii. White/Caucasian', 56::int),
    ('HST 002', 2, NULL, NULL, NULL, 'iii. Asian/Mongoloid iv. Native American/Amerindian v. Pacific Islander/Australoid', 57::int),
    ('HST 002', 3, '2', 'Major World Civilisations', 'Concept of civilisation; importance; major world civilisation', 'Concept of civilisation i. The stage of human social and cultural development ii. The process of which a society or place reaches an advanced stage of social and cultural development and organisation. iii. The advanced stage of human society containing highly forms of government, culture, industry and common social norms. Importance of civilisation. It promotes:
iv. Collective advancement and efficiency v. Safety and security vi. Cultural and intellectual growth vii. Societal structure viii. Material and spiritual development etc Major World Civilisation
1. Egyptian civilisation:
Invention of the art of writing, Medicine: surgery and mummification, Pyramids Nile river Astronomy, Contribution in mathematics (addition, subtraction, multiplication), development of irrigation and dams etc.', 57::int),
    ('HST 002', 4, NULL, NULL, NULL, '2. Mesopotamia:
Invention of glass, Cuneiform form of writing, irrigation system (use of levees and canals), Code of Hammurabi, Contributions to the field medicine (orthodox and spiritual modes of treatments) etc.', 58::int),
    ('HST 002', 5, '3', 'Introduction to Economic History', 'Concept of Economic History; fundamental concept in economic history; economic growth and development; factors of growth;', 'Concept of Economic History i. As the branch of general history dedicated to the study of past economic activities of man including agricultural, non-agricultural, trade and commerce, currency system, crafts and vocations, transportation and communication and other productive activities of man ii. As a branch of history with of actual human practice with respect to the material bases of life. Fundamental Concept in Economic History:
i. Feudalism ii. Mercantilism and Laissez faire iii. Capitalism iv. Socialism Growth Factors for growth:
i. Capital formation,', 58::int),
    ('HST 002', 6, NULL, NULL, NULL, 'ii. skilled manpower, iii. natural endowment, iv. conducive political climate, v. scientific and technological advancement, vi. availability of basic infrastructural facilities ii. Development Measurement of economic development:
i. gross national product (GDP), ii. gross national product per capital, iii. welfare approach, iv. social indicator or basic need approach.', 59::int),
    ('HST 002', 7, '4', 'Prince Henry the Navigator', 'His Roles in Promoting Exploration, Other Factors that Aided the Voyages of Exploration', 'i. The school of navigation ii. Construction of ocean going vessels powered by wind iii. Training of navigators from parts of Europe iv. Scientific equipment for navigation v. Pioneered the exploration of Africa.', 59::int),
    ('HST 002', 8, '5', 'Africans in the Diaspora since Antiquity', 'Historical image of Africa and major features of the continent; the meaning of diaspora, The trans-Atlantic Slave Trade/The Triangular Trade and its Consequences,', 'Historical image and major features of Africa i. Africa is the second largest continent in the world. ii. Second most populous. iii. Cradle of the human race (supported by the Olduvai Gorge in Tanzania) iv. Geographic survey of Africa (maps: identify the countries', 59::int),
    ('HST 002', 9, NULL, NULL, 'contributions of Africans in Diaspora to the world', 'and regions) the continent has 54 countires v. Landforms and Plateau (Sahara Desert, Mount Kilimanjaro, Great Rift valley) vi. Major Rivers and Lakes (Rivers Nile, Congo and Niger; Lake Victoria and Tanganyika) vii. Rich Natural Resources (gold, oil, diamonds, copper, uranium, lithium and fertile agricultural land) viii. Diaspora refers to the scattering or dispersion of African people from their original homeland to other parts of the world. ix. Types of diaspora: Voluntary and involuntary diaspora. The trans-Atlantic Slave Trade/The Triangular Trade and its Consequences i. Brief history of the Trans-Atlantic Slave Trade ii. Mass movement of Africans to the New World iii. Depopulation of the African continent (the most productive populace-labour force-were moved) iv. Disruption of Africa’s economic progress v. Incessant slave raiding and conflict vi. Introduction of strange diseases', 60::int),
    ('HST 002', 10, NULL, NULL, NULL, 'vii. Dehumanisation effect viii. It paved the way for colonialism ix. Long-term racism and colonisation x. Social and cultural breakdown xi. Political fragmentation Contributions of Africans in Diaspora to the world:
i. Provision of labour force ii. Sports and entertainment iii. Knowledge production', 61::int),
    ('HST 002', 11, '6', 'The American Revolution/War of Independence and its aftermath', 'Factors that Led to the Revolution', 'i. Opposition to British rule ii. Resistance to taxation iii. Unilateral declaration of independence iv. Political Freedom on the part of the Thirteen colonies v. British Adoption of the policy of Mercantilism vi. British Navigation Acts vii. Stamp Acts viii. Boston Tea Party etc', 61::int),
    ('HST 003', 1, '1', 'Types of Colonial Administrative Systems in Africa', 'Indirect Rule, Assimilation/Association, and Paternalism.', 'Meanings/definition of terms.', 62::int),
    ('HST 003', 2, '2', 'Indirect Rule in Nigeria', 'Indirect Rule in Northern Nigeria, in South Western Nigeria And South Eastern Nigeria.', 'Reasons for the introduction of indirect rule; successes and failures of the policy in the three regions.', 62::int),
    ('HST 003', 3, '3', 'Assimilation/ Association policies in Senegal', 'Assimilation in the Four Communes of Dakar, Goree, Rufisque and Saint Louis, Association.', 'i. Reasons for the introduction, successes and failures of Assimilation policy. ii. Features of the policy of Association in French West Africa', 62::int),
    ('HST 003', 4, '4', 'British rule in East Africa', 'British East African Protectorate, Emergence of Kenya as Settler Colony.', 'i. Administration and development up till 1920. ii. Reasons for emergence of kenya as a White Settlers’ colony.', 62::int),
    ('HST 003', 5, '5', 'Decolonisation Process in East Africa', 'Emergence of Kikuyu Movement and Mau Mau Uprising, The role of Jomo Kenyatta in Nationalist Struggles.', 'Reasons for the emergence of Kikuyu Movement and the outbreak of Mau Mau Uprising, Leadership roles of Jomo Kenyatta.', 62::int),
    ('HST 003', 6, '6', 'Establishment of Colonial Rule in North Africa', 'French Occupation of Algeria in 1830, Emergence of Resistance, Algerian War of Independence (1954-1962).', 'i. Motives for the French occupation of Algeria ii. Reasons for resistance to the occupation. iii. Factors that motivated the outbreak of the Algerian War of Independence and its consequences.', 62::int),
    ('HST 003', 7, '7', 'Colonial Rule in South Africa', 'The Establishment of the Union of South Africa in 1910, Emergence of African Resistance,', 'i. Reasons for the emergence of the Union. ii. Factors that aided the emergence of African resistance.', 62::int),
    ('HST 003', 8, NULL, NULL, 'Emergence of Apartheid Policy in 1948, African Resistance to Apartheid, Incarceration of Nelson Mandela, Majority Rule Since 1994.', 'iii. Motivations for the introduction of apartheid policy. iv. Reasons for the incarceration of nelson Mandela. v. Nelson Mandela: Release from prison and emergence of majority rule since 1994.', 63::int),
    ('HST 003', 9, '8', 'The OAU/AU', 'The Formation of OAU and Transformation to AU. i', 'i. The establishment of OAU in 1963. ii. The successes and failures of OAU. ii. Reason for transformation to AU in 2002.', 63::int),
    ('HST 004', 1, '1', 'Industrial Revolution in Britain', 'Factors that Aided Industrial Revolution in Britain, Impact of Industrial Revolution on British Society', 'Factors:
i. Availability of raw materials e.g. iron and coal ii. Invention: steam engines Agricultural Revolution of 18th century i. Availability of finance ii. Availability of entrepreneurs iii. Technological changes (inventions of machines like the Spinning Jenny in 1764 by James Hargreaves; the power loom by Edmund Cartwright in 1787; the', 63::int),
    ('HST 004', 2, NULL, NULL, NULL, 'steam engine by James Watt in the 1760s among others) iv. Inventions in transportation. Impact:
i. Rural-urban migration ii. International trade iii. Abolition of slave trade etc.', 64::int),
    ('HST 004', 3, '2', 'The Evolution of Modern State System', 'The 30 Years’ War and the Treaty of Westphalia of 1648', 'i. Reasons for the 30 Years’ War ii. Provisions of the Treaty iii. Impact of the Treaty of Westphalia on modern State System.', 64::int),
    ('HST 004', 4, '3', 'The French Revolution of 1789', 'Causes of the French Revolution', 'i. Summoning of the Estate Generales ii. Oppressive taxation of the Third Estate iii. The impact of American Revolution iv. Poor harvest of 1787 v. The influence of the philosophers/intellectuals', 64::int),
    ('HST 004', 5, '4', 'Vienna Congress of 1815', 'Reasons for the Congress of Vienna and its aftermath, Resolutions of the Congress, Limitations/ weaknesses of the resolutions of the Congress', 'Reasons:
i. To redraw the map of Europe after the Napoleonic wars (1794-1814) ii. To maintain balance of power Resolutions:
i. Principles of legitimacy ii. Territorial rearrangement and distribution iii. Principles of diplomatic protocols iv. Establishment of Concert System: the Congress of Aix-la-Chapelle etc… v. Independence of Switzerland', 64::int),
    ('HST 004', 6, NULL, NULL, NULL, 'Limitations:
i. Neglect of nationalism ii. Containment of the idea of liberalism', 65::int),
    ('HST 004', 7, '5', 'Unification of Germany', 'Factors that aided the unification of Germany', 'Factors:
i. The rise of nationalism ii. Resolution at the Vienna Congress of 1815 iii. The unification of Italy iv. The role of Otto Von Bismarck v. Denmark-Prussia war of 1864 vi. Austria-Prussia war of 1866 vii. The Franco-Prussia war of 1870', 65::int),
    ('HST 004', 8, '6', 'World War I', 'Reasons for World War I', 'Reasons:
i. The alliance system (triple alliance and Triple Entente) ii. Arms race iii. Balkan crisis iv. The collapse of balance of power v. Rivalry among great powers over territories in Africa vi. The assassination of Archduke Ferdinand', 65::int),
    ('HST 004', 9, '7', 'The Versailles Treaty of 1919', 'Provisions of the Treaty', 'Article 231 (war indemnity clause/reparation clause) i. The establishment of the League of Nations ii. Redrawing of the map of Europe; among others Note: mindful of the fact that many of the clauses were either ignored or not implemented.', 65::int),
    ('HST 004', 10, '8', 'The League of Nations', 'Reason for the Establishment of League of Nations, Successes and Failures', 'Reasons:
i. To maintain world peace and end wars forever Successes:', 65::int),
    ('HST 004', 11, NULL, NULL, NULL, 'i. It promoted world peace between 1920 to 1938 ii. Promotion of agricultural developments iii. Advancement of medicine; among others Failures:
i. Failure to enforce provisions of the Versailles Peace Treaty ii. Outbreak of the Second World War iii. Lack of standing army iv. The absence of United States and Russia v. The policy of Appeasement by Britain and France; among others…', 66::int),
    ('HST 004', 12, '9', 'World War II and the Formation of the UNO', 'Causes of the War, Effects of the War', 'Causes of the war:
i. The policy of Appeasement by Britain and France ii. The failure of the League of Nations iii. The Nazi propaganda under Adolf Hitler iv. aggressive foreign policies of Japan and Italy v. The invasion of Poland by Germany; and others Effects:
i. Collapse of European economies ii. Mass destruction of lives and property in Europe and Asia (Japan’s Hiroshima and Nagasaki) iii. Starvation and death iv. Formation of the UN', 66::int),
    ('IGB 001', 1, '1', 'Orthography of Nigerian Languages', 'i.Definition of orthography ii.Classification of orthography ii. Principles of orthography iv. Types of Orthography v. Survey of orthography in Nigerian languages vi. Problems and prospects-Igbo Language Orthography and its controversy.', 'The Focus of this course is on the orthography i.e., standardized system of writing Igbo language and its challenges, understanding and knowledge of phonology, speech sound system, syllable structure, and the phonological processes that', 70::int),
    ('IGB 001', 2, NULL, NULL, 'vii. Challenges of orthography design in the age of Information and Communication Technology (ICT).', 'take place when they are found in utterances. Igbo speech sound system i. vowels and consonants, place and manner of articulation, state of glottis, etc. ii. syllable: structure C.V. and N. iii. phonological processes:
vowel harmony, assimilation, elision, etc. iv. Igbo tones: high, low & step, tonal change, etc. v. loan words vi. phonetic transcription of Igbo sounds and words vii. Basics of Linguistic Studies', 71::int),
    ('IGB 001', 3, '2', 'Introduction to Igbo Phonology', 'i. Definition of phonology and phonetics ii. Relationship between phonetics and phonology iii. Principles of phonology and phonetics iv. Classification of phonetics v. The Phoneme vi. Distinctive Features', NULL, 71::int),
    ('IGB 001', 4, '3', 'Igbo Speech Sounds', 'i. Consonants ii. Vowels', NULL, 71::int),
    ('IGB 001', 5, '4', 'Syllable Structure', 'i. V = vowel only ii. CV = consonant with vowel iii. SN/SV = Syllabic nasal/semi-vowel', NULL, 71::int),
    ('IGB 001', 6, '5', 'Types of phonological Processes in Igbo', 'i. Vowel Harmony ii. Vowel Assimilation iii. Vowel Elision iv. Consonant Elision v. Coalescence', NULL, 71::int),
    ('IGB 001', 7, '6', 'Igbo Tones', 'i. / = High Tone ii. \ = Low Tone i. ̶ = Step Tone', NULL, 71::int),
    ('IGB 001', 8, '7', 'Transcription of Igbo Speech Sounds, etc.', 'i. Transcription of Igbo Speech Sounds ii. Transcription of Igbo words Transcription of Igbo expressions.', NULL, 72::int),
    ('IGB 001', 9, '8', 'Adaptation of words and coinages', 'ii. Words and expressions loaned from other languages New words and phrases neologised into the Igbo language as a result of inventions, etc.', NULL, 72::int),
    ('IGB 001', 10, '9', 'Introduction to Linguistics 11', 'i. Definition of Linguistics ii. Acoustic phonetics iii. Study of frequency-pitch- related to tone iv. Tools used for acoustic phonology: spectrograms, waveforms. The software is Praat.', NULL, 72::int),
    ('IGB 002', 1, '1', 'Genres and Scope of Oral Igbo Literature', 'i. Definition of Oral literature ii. Genres of Oral Literature iii. Abụ ọnụ (Oral Poetry) iv. Akọmakọ ọnụ (Oral Prose Narrative) v. Ejije ọnụ (Oral Drama)', 'Igbo oral literature has three subdivisions which are poetry, prose and drama. Students are taken through the rudiments of each subdivision. a. Prose narratives (akọmakọ) i. ifo (folktales) its types ii. nkọmịrịkọ (myth) iii. nkọkịrịkọ (legend) iv. yamere (aetiology) v. ụkabụilu (anecdote) vi. asịnilu (parable) vii. ilu (proverb) viii. nkọnilu (allegory) ix. akpaalaokwu (idioms), etc. b. Poetry (abụ i. abụ akwamozu (elegiac poetry) ii. abụ alụmdi (marriage poetry) iii. abụ ọmụmụ nwa (birth poetry) iv. abụ agha (war poetry) v. abụ echichi (title-taking poetry), etc. c. Drama (Ejije) i. ejije mmọnwụ (mmọnwụ drama)', 73::int),
    ('IGB 002', 2, '2', 'The Sub-genres of Oral Igbo Poetry', 'i. Abụ Agha (War Poetry) ii. Abụ Akwamozu (Funeral Poetry) iii. Abụ Alụmdi (Marriage Poetry) iv. Abụ Echichi (Title-Taking Poetry) v. Abụ Ntọaja (Ritual Poetry) vi. Abụ Nwa (Birth Poetry) vii. Abụ Otito (Panagyrics)', NULL, 73::int),
    ('IGB 002', 3, '3', 'The Sub-genres of Oral Igbo Prose Narrative', 'i. Ifo/Iduu (Folk Narrative) ii. Nkọmịrịkọ (Myth) iii. Nkọkịrịkọ (Legend) iv. Yamere (Aetiology) v. Nkọnilu (Allegory)', NULL, 73::int),
    ('IGB 002', 4, NULL, NULL, 'vi. Ụkabụilu (Anecdote) vii. Gwamgwamgwam (Riddles)', 'ii. ejije eshe (eshe funeral drama) iii. ejije ekpe (ekpe drama), etc.', 74::int),
    ('IGB 002', 5, '4', 'The Sub-genres of Oral Igbo Drama', 'i. Ejije Mmọnwụ (Mmọnwụ Drama) ii. Ejije Eshe (Eshe Funeral Drama) iii. Ejije Ekpe (Ekpe Dance Drama) iv. Ejije keonyonyo (Animated Igbo drama)', NULL, 74::int),
    ('IGB 002', 6, '5', 'Documentatio n of Oral Literature', 'i.Definition of Documentation ii.Aims of Documentation iii.Types of Documentation iv.Challenges of Documentation', NULL, 74::int),
    ('IGB 002', 7, '6', 'Technology and Content Creation in Igbo Orality', 'i.Definition of Technology ii. Content Creation iii.Types of Content Creation iv.Artificial Intelligence (AI) and Content Creation', NULL, 74::int),
    ('IGB 003', 1, '1', 'Syntax of Igbo Language', 'i. Adjective ii. Adverb iii. Noun iv. Preposition v. Verb', 'The course is an introductory study of Igbo language system comprising of theoretical linguistics (morphology, syntax), Sociolinguistics and Applied linguistics, as well as aspects of orthography and translation. The Igbo word classes represent the foundation of syntax, emphasising aspects of Nominalisation, the verb, adjectives, adverbs, and preposition. This is in addition to typology of sentences.', 75::int),
    ('IGB 003', 2, '2', 'Phrase Formations in Igbo', 'i. Noun Phrase ii. Verb Phrase iii. Adjective Phrase iv. Preposition Phrase', NULL, 75::int),
    ('IGB 003', 3, '3', 'Various Sentence Types in Igbo', 'i. A typology of sentences in Igbo: ii. Simple sentence iii. Compound sentence iv. Declarative sentence v. Negative sentence vi. Interrogative sentence vii. Topical sentence, etc.', NULL, 75::int),
    ('IGB 003', 4, '4', 'Advanced Comprehension and Composition I', 'i. Composition ii. Conventions of Composition iii. Spelling iv. Punctuation v. Structure vi. Types of composition vii. Narrative viii. Explanatory ix. Argumentative x. Dialogue xi. Letter Writing, etc. xii. Comprehension Exercises', 'The focus of Morphology is on the morpheme and typology as well as word formation processes in Igbo. Sociolinguistics and Applied linguistics are focused on language use in the society as well as how language is applied to solve problems in society.', 76::int),
    ('IGB 003', 5, '5', 'Introduction to Linguistics', 'i. Definition of Linguistics ii. Aims of Linguistics iii. Branches of Linguistics iv. Descriptive (syntax, morphology, phonology, semantics) v. Sociolinguistics vi. Applied linguistics, etc.', NULL, 76::int),
    ('IGB 003', 6, '6', 'Morphology of the Igbo Language', 'i.Definition of morphology ii. The Word and Structure iii. The Morpheme iv. Types of Morpheme v.Morphological Processes (affixation, compounding, reduplication, etc) vi.Word formation processes in Igbo.', NULL, 76::int),
    ('IGB 003', 7, '7', 'Orthography of Nigerian Language', 'i.Definition of Orthography ii. Types of Orthography iii.Orthography Development in Nigeria iv. Efforts of missionary groups in orthography development', NULL, 76::int),
    ('IGB 003', 8, '8', 'Introduction to sociolinguistics', 'i. Definition of Sociolinguistics', NULL, 76::int),
    ('IGB 003', 9, NULL, NULL, 'ii. Language Choice iii. Language Attitude iv.Bilingualism and multilingualism v. Language Maintenance and Shift, etc.', NULL, 77::int),
    ('IGB 003', 10, '9', 'Introduction to Applied Linguistics', 'i. Definition of Applied Linguistics ii. Scope and Categories iii.Language in Education iv.Mother Tongue Education v.Psycholinguistics vi.Ecolinguistics vii. Forensic linguistics, etc', NULL, 77::int),
    ('IGB 003', 11, '10', 'Introduction to Translation', 'i. Definition of Translation ii.Aims of Translation iii. Types of Translation iv.Direct translation (word to word, literal); v. Indirect translation (equivalence, paraphrasing, adaptation, etc)', NULL, 77::int),
    ('IGB 004', 1, '1', 'The development and growth of written Igbo Literature', 'i. Igbo Word Compilation and Documentation Period (1766 – 1857) ii. Igbo literature Translated from foreign literatures (1857-1932)', 'A preliminary study of the development, growth, Written Igbo Literature, and genres of Written Igbo Literature: poetry, prose and drama exemplified by selected works a. Written Igbo Literature
– The novel (early Igbo novel 1933 – 1970) b. Written Igbo poetry
– A survey of written Igbo poetry c. Written Igbo Drama', 78::int),
    ('IGB 004', 2, '2', 'Written Igbo literature', 'i. Definition of Written Igbo Literature ii. Importance of Written Igbo Literature iii. Features of Written Igbo Literature iv. Types of Igbo Literature (Oral and Written) v. Differences between Oral and Written Igbo Literature vi. The Genres of Written Igbo Literature a. Abụ Ederede (Written Poetry', NULL, 78::int),
    ('IGB 004', 3, NULL, NULL, 'b. Iduuazị/Akọmakọ Ederede (Novel/Written Igbo Prose Narrative) c. Ejije Ederede (Written Drama) vii. Artificial Intelligence as a tool in creative writing of Igbo Literature. viii. Sources of events in Igbo literary works ix. The Basis for Analyzing Igbo Literature a. Theme b. Setting c. Character d. Plot e. Point of view f. Style/Language g. Tone of voice', NULL, 79::int),
    ('IGB 004', 4, '3', 'Written Igbo Poetry', 'i. A Survey of Written Igbo Poetry (1975 – Date) i. Definition of Written Igbo Poetry ii. Features of Written Igbo Poetry iii. Types of Written Igbo Poetry iv. Analysis of Written Igbo Poetry a. Content: Topic/Sub-Topic b. Form: Structure, Rthym, and Language', NULL, 79::int),
    ('IGB 004', 5, '4', 'Written Igbo Novel', 'i. The Emergence of Igbo Novel (1933 -1970) ii. The Transitional Gap Period/War Period (1967 – 1972) iii. The Revival of Written Igbo Novel/Written Igbo Prose Narrative (1973 – Date) iv. Definition of Igbo Novel v. Features of Igbo Novel vi. Types of Novels vii. Analysis of Igbo Novel a. Content: Topic/Sub-Topic b. Form: Narrative device, Agwa, and Language', NULL, 80::int),
    ('IGB 004', 6, '5', 'Written Igbo Drama', 'v. Written Igbo Drama (1974 – Date) vi. Definition of Writen Igbo Drama vii. Features of Written Igbo Drama viii. Types of Written Igbo Drama ix. Analysis of Written Igbo Drama c. Content: Topic/Sub-Topic d. Form: Dramatic Convention, Structure, Character, and Language', NULL, 80::int),
    ('ISS 001', 1, '1', 'Appraising the Jāhiliyyah Period', 'i) Meaning and Features of Jāhiliyyah ii) Ancient Arab Personality and Society iii) Shirk: Polytheistic Practices.', 'i) Discus reasons for using the term ‘Jāhiliyyah’ for the Pre-Islamic Period.
ii) Highlight Jāhiliyyah Practices.', 86::int),
    ('ISS 001', 2, NULL, NULL, 'iv) Wa’d, Ribā, Raids and Internecine wars, Alcoholism, Gambling, Immorality and Low Status of Women.', NULL, 87::int),
    ('ISS 001', 3, NULL, NULL, 'v) Islamic Reforms to Jāhiliyyah Practices vi) Tawhīd as Replacement of Shirk. vii) Prohibition of different forms of Economic Exploitation and Indecent Acts.', 'i) Distinguish between Jāhiliyyah and Islamic Era.
ii) List the Reforms Islam introduced.', 87::int),
    ('ISS 001', 4, '2', 'Muhammad’s Early Life', 'Birth and Childhood i) Significance of the Prophet’s Birth in cĀmul-Fīl ii) His Childhood under: a) Halīmatus-Sacdiyyah b) Amīnah c) cAbdul-Muttalib d) Abū Tālib', 'i) Relate theme of Sūratul-Fīl to Muhammad’s Birth
ii) Analyse Muhammad’s childhood experiences with Halīmatus-Sacdiyyah, Amīnah, cAbdul-Muttalib and Abū Tālib.', 87::int),
    ('ISS 001', 5, NULL, NULL, 'iii) Muhammad’s Childhood Attributes especially the nickname Al-Amīn', 'Justify the reasons behind Muhammad’s nickname Al-Amīn and other attributes that earned him love among the Quraysh', 87::int),
    ('ISS 001', 6, NULL, NULL, 'Marriage to Khadījah iv) Muhammad as Khadījah’s Employee v) Marriage with Khadījah vi) Khadījah’s children', 'i) State the circumstances of his marriage to Khadījah
ii) List Khadījah’s children', 87::int),
    ('ISS 001', 7, NULL, NULL, 'vii) Muhammad’s Role in Re-building the Kacbah viii) Disagreement among the Quraysh over the Black Stone viii) Sound Judgement of the Prophet (SAW)', 'Describe Muhammad’s Role in Reconstructing the Kacbah', 87::int),
    ('ISS 001', 8, '3', 'Mission in Makkah', 'i) Muhammad’s Life of Meditation and Contemplation in the Cave Hirā’ ii) Call to Prophethood iii) The First Qur’ānic Revelation', 'i) Explain the reasons for his meditation
ii) Discus the Call to Prophethood
iii) Describe his encounter with Angel Jibril', 88::int),
    ('ISS 001', 9, NULL, NULL, 'Makkan Opposition and Persecution iv) Private and Public Preaching v) Early Converts vi) Dimensions of Makkan Opposition vii) Persecution of Early Muslims', 'i) Trace the commencement of Da`wah
ii) Identify early coverts
iii) Examine reasons and nature of Makkan opposition and persecution', 88::int),
    ('ISS 001', 10, NULL, NULL, 'Process of the Hijrah viii) Causes of the Hijrah ix) Migration to Abyssinia x) The Year of Sorrow xi) Visit to Taif xii) The Pledges of Aqabah xiii) The Hijrah & Its Significance', 'i) Identify causes of the Hijrah
ii) Describe the migrations to Abyssinia
iii) Discus various events preceding the Hijrah', 88::int),
    ('ISS 001', 11, '4', 'Mission in Madinah', 'i) Establishment of the Ummah ii) The Muhājirūn and Ansār iii) Settling the Feud between Aws and Khazraj iv) Constitution of Madīnah', 'i) Discus the founding of the Ummah in Madīnah
ii) Examine the contents of the Constitution of Madinah', 88::int),
    ('ISS 001', 12, NULL, NULL, 'The Battles v) The Battle of Badr vi) The Battle of Uhud vii) The Battle of Khandaq', 'i) Distinguish between the causes, nature and outcomes of the Battles of Badr, Uhud and Khandaq', 88::int),
    ('ISS 001', 13, NULL, NULL, 'viii) The Treaty of Hudaybiyyah ix) Causes of the Treaty x) Significance and Lessons of the Treaty', 'i) Narrate causes of Treaty of Hudaybiyyah
ii) Analyse the terms of the Treaty', 88::int),
    ('ISS 001', 14, NULL, NULL, NULL, 'iii) State significance of the Treaty', 89::int),
    ('ISS 001', 15, NULL, NULL, 'Conquest of Makkah and Farewell Pilgrimage xi) Causes of the Conquest of Makkah xii) Conquest of Makkah xiii) Farewell Pilgrimage and Farewell Khutbah', 'i) Identify causes of Conquest of Makkah
ii) Describe nature of the Conquest
iii) Highlight the significance of the Farewell Sermon', 89::int),
    ('ISS 001', 16, NULL, NULL, 'xiv) Death and Muhammad’s Character', 'i) State how the Prophet passed on
ii) List Muhammad’s Character', 89::int),
    ('ISS 001', 17, '5', 'The Khulafā’ Rāshidūn', 'Life and Achievements of i) Abū Bakr As-Siddīq ii) cUmar b. Al-Khattāb iii) Uthmān b. cAffān iv) Alī b. Abī Tālib', 'i) Discuss lives of the Khulafā’ Rāshidūn
ii) Establish differences between the tenure of the Khulafā’ Rāshidūn and their achievements', 89::int),
    ('ISS 001', 18, '6', 'Life and Achievements of cUmar ibn cAbdul-`Azīz and Hārūn ar-Rashīd', 'i) Life and Achievements of `Umar ibn `Abdul-`Azīz ii) Life and Achievements of Hārūn ar-Rashīd', 'i) Discuss lives of `Umar ibn Al-`Abdul-`Azīz and Hārūn ar-Rāshīd
ii) Establish differences between the caliphates of cUmar ibn cAbdul-cAzīz and Hārūn ar-Rashīd
iii) Highlights their achievements', 89::int),
    ('ISS 001', 19, '7', 'Impact of the spread of Islam to Africa', 'i) Spread of Islam to West, North, East and Central Africa ii) Factors Responsible for the Diffusion of Islam in W/A iii) Impact of the spread of Islam to West Africa', 'i) Examine factors responsible for the spread of islam in West, North, East and Central Africa
i) Discuss factors responsible for the diffusion of Islam in W/A', 89::int),
    ('ISS 001', 20, NULL, NULL, NULL, 'ii) Assess the impact of the spread of Islam to West Africa', 90::int),
    ('ISS 001', 21, '8', 'The Hausa-Fulani Jihād', 'i) Causes, Trends and Outcome of the Hausa-Fulani Jihād ii) Personalities involved in the Jihad', 'i) Discuss causes and trend of the Sokoto Jihad
ii) Examine the outcome of the Hausa-Fulani Jihād', 90::int),
    ('ISS 001', 22, '9', 'The Kanem-Bornu Empire', 'Rise and Decline of Kanem-Bornu Empire i) Founding by the Kanembu ii) The Sayfawa Dynasty iii) Achievements of the Mais iv) Decline of Kanem-Bornu', 'Discuss the founding, rise and decline of the Kanem-Bornu Empire', 90::int),
    ('ISS 002', 1, '1', 'Imān as Foundation of Islam', 'i) Definition and Components of Imān ii) The Six (6) Articles of Faith', 'i) Define Imān literally and technically
ii) List components of Imān
iii) Discuss implications of belief in the Articles of Faith', 91::int),
    ('ISS 002', 2, NULL, NULL, 'iii) Types of Tawhīd a) Tawhīd ar-Rubūbiyyah b) Tawhīd al-Ilāhiyyah c) Tawhīd al-Asmā’ was-Sifāt', 'Identify the main types of Tawhīd', 91::int),
    ('ISS 002', 3, '2', 'Shirk As Unpardonable Sin', 'i) Meaning and Forms of Shirk ii) Manifestations of Shirk iii) Implications of engaging in Shirk iv) Relationship between Kufr and Shirk', 'i) Define Shirk and identify forms of Shirk
ii) Identify modern manifestation of Shirk and its implications', 91::int),
    ('ISS 002', 4, '3', 'An Exposition on the Sharīcah', 'i) Literal & Technical Definitions of Sharī cah and its misconception ii) Differences between: a) Sharīcah, Islam and Fiqh b) Sharī cah and Man-Made Laws', 'i) Distinguish between the literal and technical meanings of Sharīcah
ii) Differentiate between Sharī cah and man-made laws', 91::int),
    ('ISS 002', 5, NULL, NULL, 'Sources of the Sharī cah iii) Primary Sources iv) Secondary Sources v) Tertiary Sources vi) Human Acts under the Sharīcah vii) Categorisation of Human Acts', 'i) Discuss sources of the Sharī cah
ii) Categorise human acts in Islamic Jurisprudence', 91::int),
    ('ISS 002', 6, '4', 'The Islamic Concept of cIbādah', 'i) Definition of cIbādah ii) Misconception about cIbādah iii) Scope and Dimensions of cIbādah iv) Purposes of cIbādah', 'ii) Define cIbādah literally and technically
ii) Identify misconception about cIbādah
iii) Discuss scope and dimensions of cIbādah', 91::int),
    ('ISS 002', 7, '5', 'Forms and Purposes of Tahārah', 'i) Types of water for Tahārah ii) Ghusl and its types iii) Wudū iv) Tayammum v) Significance of Tahārah', 'i) List the forms of Tahārah
ii) Demonstrate how various forms of purification are performed
iii) Discuss the purposes of Tahārah', 92::int),
    ('ISS 002', 8, '6', 'The Observance, Types and Values of Salāt', 'i) Categories of Salāt (Obligatory & Superogatory) ii) Description of A rakacah iii) Joining Salātul-Jamācah iv) Amendment of Salāt (Sujud Sahw)', 'i) Categorise various types of salāt
ii) Demonstrate how salāt is performed
iii) Describe how corrections are made in Salat', 92::int),
    ('ISS 002', 9, '.7', 'Zakāh and Sadaqah', 'i) Meaning & Objectives of Zakat ii) Conditions of Payment iii) Zakatable Items & Amounts Due iv) Beneficiaries of Zakāh v) Significance of Zakāh vi) Distinction between Zakah and Sadaqah', 'i) Distinguish between Zakāh and Sadaqah
ii) Justify payment to specified beneficiaries
iii) Analyse significance of Zakāh in eradication of poverty', 92::int),
    ('ISS 002', 10, '8', 'The Regulations Governing Sawm,', 'i) Definition and Types of Fasting ii) Ramadan Fasts iii) Conditions for the validity of Fasting iv) What Vitiates Fasting v) Those Exempted from Fasting', 'i) Describe how sawm is observed and what vitiates it
ii) Identify the types of fasts
iii) List those exempted from fasting', 92::int),
    ('ISS 002', 11, '9', 'Hajj and Umrah', 'i) Meaning and Purpose of Hajj ii) Distinction between Hajj and Umrah iii) Conditions for the validity of Hajj iv) Hajj Rites and how they are Performed v) Significance of Hajj', 'i) Distinguish between Hajj and Umrah
ii) List the conditions of Hajj', 92::int),
    ('ISS 002', 12, '10', 'The Islamic Marriage Regulations', 'i) Meaning and Purposes of Nikāh ii) Conditions of Validity (Ijāb & Qubūl, Wilāyah, Mahr & Witnesses) iii) Marital Responsibilities and Rights iv) Prohibited Marriages (Permanent & Temporary Prohibitions)', 'i) Evaluate the uniqueness of Nikāh
ii) Discuss conditions of validity of Nikāh
iii) Illustrate marital responsibilities', 93::int),
    ('ISS 002', 13, '11', 'Regulations on Ṭalāq', 'i) Meaning and Types of Ṭalāq (Faskh, Liān, Khulc, Mubāra`ah, Zihār) ii) Ṭalāq as Reprehensible Act iii) Reconciliation is Encouraged iv) Categorisation of Ṭalāq (revocable and irrevocable)', 'i) State Islamic position on Ṭalāq
ii) Categorise Ṭalāq into revocable and irrevocable', 93::int),
    ('ISS 002', 14, NULL, NULL, 'v) The cIddah: Meaning, Types & Purposes of cIddah vi) Custody of Children after Divorce', 'ii) Discuss regulations governing cIddah and its purposes
ii) Explain provisions on child custody after divorce', 93::int),
    ('ISS 003', 1, '1', 'Names and Attributes of the Qur’ān.', 'i) Definition of the Qur’ān ii) Names and Attributes of the Qur’ān iii)Themes of the Qur’ān', 'i) Identify names and attributes of the Qur’ān
ii) Extract themes of the Qur’ān.', 94::int),
    ('ISS 003', 2, '2', 'Authenticity of the Qur’ān as a Divine Book', 'i) Divine Origin of the Qur’ān ii) Qur’ān as a miracle a) Its Inimitability b) Its Incorruptibility c) Scientific Miracle d) Accuracy of Historical Records e) The Predictions f) Unlettered Muhammad iii) Differences Between the Qur’ān & other Scriptures', 'i) Justify the divine authorship of the Qur’ān
ii) Differentiate between the Qur’ān from other scriptures.', 94::int),
    ('ISS 003', 3, '3', 'Modes and Places of Revelation', 'i) Definition and Stages of Qur’ānic Revelation ii) Modes of Revelation iii) Places of Revelation (Makka & Madinah)', 'i) Discuss stages of Qur’ānic revelation
ii) Relate event of the initial revelation at Hira
iii) Discuss various modes of revelation
iv) Distinguish between Makkan and Madinan Suwar', 94::int),
    ('ISS 003', 4, '4', 'Preservation and Compilation of the Qur’ān', 'i) Mechanisms of Preserving the Qur’ān ii) Compilation of the Qur’ān: a) During the life of Prophet Muhammad b) During the time of Abubakr iii) Emergence of ar-Rasm al-`Uthmānī', 'i) Identify the mechanisms used for preserving the text of the Qur’ān
ii) Discuss the compilation of the Qur’ān during the era of the Prophet, Abubakr and Uthman', 94::int),
    ('ISS 003', 5, '5', 'Asbābun-Nuzūl and an-Nāsikh wal-Mansūkh', 'i) Meaning of Asbābun-Nuzūl ii) The Significance of Asbābun-Nuzūl,', 'i) Explain the meaning and importance of Asbābun-Nuzūl', 95::int),
    ('ISS 003', 6, NULL, NULL, 'iii) Meaning and Types of an-Nāsikh wal-Mansūkh iv) Its relevance to Tafsīr, Fiqh etc', 'i) Discuss the meaning and importance of an-Nāsikh wal-Mansūkh to the study of the Qur’ān', 95::int),
    ('ISS 003', 7, '6', 'Tafsīr and Qur’ānic Translation', 'i. Definition and Types of Tafsīr ii) Qualities of a Mufassir iii) Development and Ethics of Translation', 'Distinguish the difference between Tafsīr and Translation', 95::int),
    ('ISS 003', 8, '7', 'A Study of the Text, Translation and Interpretation of selected chapters of the Qur’an', 'A detailed study of the recitation, translation, commentaries and teachings of the following Qur’ānic chapters (suwar): al-Fātihah, al-Muzammil, al-Muddaththir , al-‘Alaq, Qadr, Ikhlas, and -Nās,', 'i) Read and write texts of selected chapters of the Qur’ān
ii) Translate the Arabic texts into English
iii) Analyse the texts to address application to daily life', 95::int),
    ('ISS 004', 1, '1', 'Definition and Values of Hadīth', 'i) Literal & Technical definitions of Ḥadith ii) Values of Ḥadith as Source of Islamic Teachings iii) Ḥadith and Khabar iv) Ḥadith & Sunnah, v) Relationship between Ḥadith and Sunnah', 'i) Define Ḥadith literally and technically
ii) Differentiate between Ḥadith & Khabar
iii) Examine relationship between Ḥadith and Sunnah', 96::int),
    ('ISS 004', 2, '2', 'Basic Types of Hadīth', 'i) Ḥadith Nabawī and Qudsi ii) The Forms and feature of Hadīth Nabawī iii) Features of Hadīth Qudsī', 'i) Distinguish between Hadīth Nabawī and Qudusī
ii) Identify three forms of Ḥadith Nabawī', 96::int),
    ('ISS 004', 3, '3', 'Basic Form of the Hadīth', 'i) Meaning, Characteristics and types of Isnād ii) Meaning, Position and Values of the Matn', 'i) Describe the characteristics of Isnād
ii) Describe the characteristics of Matn', 96::int),
    ('ISS 004', 4, '4', 'Determining the Authenticity of Hadīth', 'i) Need for Authentication ii) Criteria for Authenticating of Ḥadith iii) Classification of Ḥadith', 'i) Justify need for authenticating Ḥadith
ii) List criteria for authenticating Ḥadith
iii) Classify Ḥadith into various categories', 96::int),
    ('ISS 004', 5, '5', 'The Ruwāt and the Muhadīthūn', 'i) The Ruwāt: Definition and Role in Evolution of Ḥadith ii) The MuḤadithūn: Definition & Roles in Development of Ḥadith Literature iii) Prominent Traditionists', 'i) Compare the activities of Ruwat to those of the MuḤadithūn
ii) Name prominent Ruwat and Muhaddithūn', 96::int),
    ('ISS 004', 6, '6', 'Compilation of Ḥadith', 'Compilation of Ḥadith during: i) The time of the Prophet', 'i) Differentiate between the mode of compilation during', 96::int),
    ('ISS 004', 7, NULL, NULL, 'ii) The time cUmar bn Abdul Azīz iii) The era of Muṣannaf iv) The Era of Ṣaḥīḥ', 'the era of the Prophet and cUmar bn Abdul Azīz
ii) Describe the role played by bn Shihāb Az-Zuhr, Imam Mālik, Ahmad bn Hambāli etc', 97::int),
    ('ISS 004', 8, '7', 'The Six Standard Works of Ḥadith', 'i) Titles and Status of the Sahhāhu Sittah ii) Features of the Six Compilation', 'i) List the names of the Sahhāhu Sittah and the compilers
ii) Discuss the features of the Sahhāhu Sittah', 97::int),
    ('ISS 004', 9, '8', 'Reading, translation, commentaries and teachings of the Prophet in selected ahadith relevant to daily life', 'Detailed Study of Ahādīth on sincerity, repentance, perseverance, truthfulness, piety, firm belief, steadfastness, hypocrites, neighbourliness, parents and application of the Ahādīth to daily life', 'i) Read and write texts of hadith on sincerity and repentance. ii)Identify any hadith on perseverance, truthfulness, iii)Discuss any tradition of the Prophet on piety, firm belief, steadfastness, hypocrites, neighbourliness
iv) Examine the application of the Ahādīth to daily life', 97::int),
    ('LIT 001', 1, '1', 'Dramatic Literature', 'Definition of Drama and Theatre', 'Different definitions of drama and theatre by various authors.', 101::int),
    ('LIT 001', 2, NULL, NULL, 'Origins of Drama/Theatre', 'Emphasis should be on ritual observances in both European (Greek) and African traditions.', 101::int),
    ('LIT 001', 3, NULL, NULL, 'Drama as Performance; Drama as Literature', 'Differences and relationship between drama and theatre.', 101::int),
    ('LIT 001', 4, NULL, NULL, 'Types/Forms of Drama', 'Tragedy, Comedy, Melodrama, Farce, Tragicomedy, etc.', 101::int),
    ('LIT 001', 5, '2', 'The Structure of Drama', 'Plot structure', 'Exposition, complications/ conflict, climax, falling action, Denouement/Catastrophe (resolution), Acts and Scenes.', 101::int),
    ('LIT 001', 6, '3', 'The Elements of Drama', 'Dialogue, action, character/ characterization, language, themes, style, setting, subject matter, etc.', 'These should include identification and discussion of details about types of characters; characteristics of dramatic dialogue, dramatic action, distinction between theme and subject matter; use of dramatic techniques', 101::int),
    ('LIT 001', 7, NULL, NULL, NULL, '(suspense, flashback, foreshadowing, etc.)', 102::int),
    ('LIT 001', 8, '4', 'The Relevance of Drama to the Society', 'Social, Political Functions of Drama', 'Drama as satire, social therapy, entertainment, mirror of society, social mobilization, instrument of change, etc.', 102::int),
    ('LIT 001', 9, '5', 'The Classical Tradition', 'Introduction to Classical Tradition in Drama.', 'Major playwrights and theorists of the classical tradition: Sophocles, Aeschylus, Euripides, Aristophanes, Aristotle, Horace, Longinus, Plato. Illustrations of aspects and traditions of Classical drama and theatre.', 102::int),
    ('LIT 001', 10, '6', 'Renaissance Traditions (Elizabethan and Jacobean drama)', 'Historical Background to Renaissance period in England.', 'Thomas Kyd, Christopher Marlowe, William Shakespeare, Ben Jonson, etc. Discussions should focus on Shakespeare and his contemporaries in England. Drama in the Elizabethan and Jacobean Ages.', 102::int),
    ('LIT 001', 11, '7', 'Modern European Drama', 'Historical Background to Modern Drama. The Modern Tradition and Playwrights', 'Henrik Ibsen, George Bernard Shaw, John Osborne, Anton Chekhov, Bertolt Brecht, Samuel Becket etc.', 102::int),
    ('LIT 001', 12, '8', 'American Drama', 'Historical Background to American Drama. The Modern Tradition and Playwrights. Afro-American Drama', 'Discussion should focus on the influence of the American society on the development of American drama. Emphasis should be placed on Eugene O’ Neill, Arthur Miller, Tennessee Williams, August Wilson, Amiri Baraka, Langston Hughes', 102::int),
    ('LIT 001', 13, '9', 'Modern African Drama', 'Historical Background to African Drama and Playwrights. Drama in Modern African Society.', 'Pre-Colonial, Colonial and Post-Colonial Drama. Wole Soyinka, J. P. Clark-Bekederemo, Zulu Sofola, Tess Onwueme, Femi Osofisan, Irene Salami, Bose Afolayan, Hope Eghagha, Ngugi wa Thiong’o, Athol Fugard, Tewfik Al-Hakim, Ahmed', 102::int),
    ('LIT 001', 14, NULL, NULL, NULL, 'Yerima, Ama Ata Aidoo, Tracie Utoh-Ezeajugh etc.', 103::int),
    ('LIT 002', 1, '1', 'Prose Fiction', 'Definition of Prose Fiction', 'Definitions of prose fiction. Historical Overview of Prose Fiction. Features of the Prose Fiction.', 103::int),
    ('LIT 002', 2, '2', 'The Development of the Novel.', 'Origin of the English Novel.', 'Role of the journals/ newspapers, women in 18th century, revolving libraries, and the rise of the middle class.', 103::int),
    ('LIT 002', 3, NULL, NULL, NULL, 'Development of the printing press and the Puritan’s ban of the theatre.', 104::int),
    ('LIT 002', 4, '3', 'Types/Forms of Prose Fiction', 'Short story, Novella, Novel, Biography, Autobiography, Memoir, Diary.', 'Discussions should include sub-categories of prose fictions such as the Gothic, Epistolary, Bildungsroman, Picaresque, Burlesque, etc.', 104::int),
    ('LIT 002', 5, '4', 'The Structure of Prose Fiction', 'The Plot Structure', 'Exposition, complications/ conflict, climax, falling action, Denouement/ catastrophe (resolution), paragraphs and chapters.', 104::int),
    ('LIT 002', 6, '5', 'The Elements of Prose', 'Character, Language, Themes, Settings, point of view,', 'The analysis should include identification and discussion of details about types of characters/ characterization; distinction between theme and subject matter; style (suspense, flashback, foreshadowing, symbolism, etc.)', 104::int),
    ('LIT 002', 7, '6', 'The Relevance of Prose to the Society', 'Functions of Prose in the Society', 'For social therapy, entertainment, mirror of society, social mobilization, instrument of change, etc.', 104::int),
    ('LIT 002', 8, '7', 'The European Prose Tradition', 'Elements of European Prose Traditions. (Realism, Surrealism, Absurdism, etc.)', 'Major prose writers of the European prose traditions that should be discussed should include: Daniel Defoe, Henry Fielding, George Eliot, Jane Austen, Samuel Richardson, Charles Dickens, Thomas Hardy, Albert Camus, Franz Kafka, Fyodor Dostoevsky, etc.', 104::int),
    ('LIT 002', 9, '8', 'African Prose Tradition', 'Historical Background to Modern African novel: Pre-Colonial, Colonial, and Post-Colonial Prose Narratives. New Generation of African Novelists:', 'The contributions of Old and New Generations of African Prose writers to the development of African Prose Traditions should be discussed. Chinua Achebe, Wole Soyinka, Elechi Amadi, Ngugi wa Thiong’o, Ayi Kwei Armah, Sembene Ousmane, Helon Habila, Sefi Atta, Chimamanda Ngozi Adichie, Chris Abani, Uzo Iweala and Segun Afolabi, Lola Shoneyin, Lola Akande, Kunle Mamudu, Idede Oseyande, Amma Darko, Nadine Gordimer', 105::int),
    ('LIT 003', 1, '1', 'The Poem', 'Definition of Poetry', 'Different definitions of poetry', 106::int),
    ('LIT 003', 2, '2', 'Traditional and Modern Poetry', 'Oral and Written Poetry', '• Features of orality: anonymity of composers/ communal ownership of texts, oral delivery, oral perception, spontaneity of composition/addition, closeness with audience. Features of written poetry:
• Individual ownership of text, authorial intention, visual perception, language perfection, distance from audience.', 106::int),
    ('LIT 003', 3, '3', 'Types/Forms of Poetry', 'Lyric, Ode, Ballad, Dirge, Epic, Sonnet, the Free Verse, Blank Verse, etc.', 'Features and examples of each sub-genre of poetry should be identified and discussed extensively.', 106::int),
    ('LIT 003', 4, '4', 'The Elements/ Characteristics of Poetry.', 'Tone, imagery, rhyme, rhythm, sound, mood, tone, settings, diction, etc.', 'Extensive discussion should take cognizance of the ways in which these elements and other poetic devices are used in making meaning in poetry.', 106::int),
    ('LIT 003', 5, '5', 'The Structure of the Poem', 'Versification, Stanza Forms, etc.', 'Lineation: couplet, tercet/teza-rima, haiku, limerick, sonnet, etc. Versification: foot, meter, etc.', 106::int),
    ('LIT 003', 6, '6', 'Poetry and Society', 'The Relevance of Poetry to Society', 'For social therapy, entertainment, mirror of society, social mobilization, instrument of change, etc.', 106::int),
    ('LIT 003', 7, '7', 'The Classical Tradition', 'Introduction to Classical Tradition in Poetry', 'Major poets and theorists of the classical tradition: Homer, Ovid, Plato, Aeneas etc.', 106::int),
    ('LIT 003', 8, '8', 'European Poetry', 'The Medieval and Renaissance Traditions', 'Historical background to Medieval and Renaissance Poetry: Geoffrey Chaucer, Sir Thomas Wyatt, Surrey, Edmund Spencer, Sir Walter Raleigh, John Milton, William Shakespeare, John Donne etc. The rise of English Language from vernacular status to acceptable', 106::int),
    ('LIT 003', 9, NULL, NULL, NULL, 'international level should be studied. Contributions of Chaucer, Wyatt, Shakespeare, and Pope as well as the features of the poetry of the Medieval, Elizabethan, Restoration and Augustan Ages should be studied.', 107::int),
    ('LIT 003', 10, NULL, NULL, '19th and 20th Centuries', 'Features of the Romantic, Victorian, and Modern Poetry.', 107::int),
    ('LIT 003', 11, '9', 'African Poetry', 'The Oral Traditions', 'Background to African Poetry: Oral and Written. Interface between the Oral and the Written forms. Anonymity and Authorship.', 107::int),
    ('LIT 003', 12, NULL, NULL, 'Modern African Poetry (written forms)', 'Features of poetry from Anglophone, Francophone and Lusophone countries. Examples of modern African poets: Niyi Osundare, Wole Soyinka, Christopher Okigbo, J.P. Clark, Kofi Awoonor, Tony Afejuku, Kola Eke, Dennis Brutus, Remi Raji, Masizi Kunene, Sola Owonibi, Tosin Gbogi, Obari Gomba, Akachi Ezeigbo, Kwame Dawes, Chris Abani, Saddiq Dzukogi, Rasak Malik Gbolahan, Lebo Mashille, Ketty Nivyabandi, Mia Couto, Agostinho Neto, Leopold Sedar Senghor, Birago Diop, Okot p’Bitek, etc.', 107::int),
    ('LIT 004', 1, '1', 'L iterary Appreciation', 'Definitions of Literary Appreciation', 'Definitions of literary appreciation which emphasize the concept of ‘close reading’ of the text.', 108::int),
    ('LIT 004', 2, '2', 'A pproaches to Literary Appreciation', 'Textual and Structural Approaches', 'Discussions should cover form and content, narrative techniques, character/ characterization, diction, figures of speech, figures of sound, genre, versification and stanza forms, visual/auditory/ tactile/aural images etc.', 108::int),
    ('LIT 004', 3, '3', 'A pproaches to Practical Criticism', 'Mimetic, Pragmatic, and Objective Approaches.', 'Introduction to psychological, and sociological approaches to text analysis in relation to the three basic approaches.', 108::int),
    ('LIT 004', 4, '4', 'U nseen Prose and Poetry', 'Unseen Prose and Poetry', 'Lecturers should guide the students in practical sessions in the analysis and criticism of unseen poetry and prose.', 108::int),
    ('MUS 001', 1, '1', 'Meaning of Music', 'Definitions of Music. Uses of Music. Properties of Musical Sound.', 'Basic definitions of music are necessary at this level. The basic properties of musical sound to include intensity, pitch, duration, timbre, etc.', 114::int),
    ('MUS 001', 2, '2', 'The Staff', 'The Clefs – Treble, Alto, Tenor and Bass Clefs. Music Alphabets. Arrangements of Music Alphabets on the Lines and Spaces of the Staff – Great Staff. Ledger lines', 'The clefs have to be drawn on the staves. The music alphabets should be placed on the lines and spaces.', 114::int),
    ('MUS 001', 3, '3', 'Musical Notes, Rests and their Durations.', 'Musical Notes and its Equivalence; Dotted Notes and its Equivalent Rest. Duration of the Notes and its Placement on the Stave. American Shape-Note', 'The duration of each notes and their interrelationships should be highlighted, and their respective technical names and values of notes.', 115::int),
    ('MUS 001', 4, '4', 'Accidentals in Music', 'Definitions, Concepts and Placement on Staff of Sharp, Flat, Double Sharp, Double Flat and the Natural Signs in Music.', 'The teachings should also emphasize not just the concepts of music theory, but the applications as well.', 115::int),
    ('MUS 001', 5, '5', 'Key Signature', 'Order of Sharps and Flats, and Circle of Fourth and Fifth.', 'Students must know how to formulate, write and derive order of sharps and flats.', 115::int),
    ('MUS 001', 6, '6', 'The Diatonic Scales', 'Major Scales; Minor Scales; Chromatic Scale; Degrees and Technical Names of Tonic Solfa Notation. Construction with or without key signatures', 'Exercises must be given on the construction of scales and their respective technical names.', 115::int),
    ('MUS 001', 7, '7', 'Transcription', 'Clef Transcriptions, Solfa and Staff Notations Transcriptions. British and American styles of solfa notation.', 'Students are expected to know how to transcribe within clefs such as treble clef, bass clef. Also, they must be able to rewrite a short piece of phrase from', 115::int),
    ('MUS 001', 8, NULL, NULL, NULL, 'staff notation to solfa notation and vice versa.', 116::int),
    ('MUS 001', 9, '8', 'Modulation', 'Changing keys in musical passages using abrupt or pivot chords.', 'Changing from a key or interval to another, modulations within a musical passage, and to another key entirely.', 116::int),
    ('MUS 001', 10, '9', 'Transposition', 'Clef Transposition, Tonal Transposition', 'To relate notes with different clefs, and to teach the foundation of orchestration and scoring for transposing instruments', 116::int),
    ('MUS 001', 11, '10', 'Time Signature', 'Simple Time and Compound Time.', 'Simple duple, triple, quadruple time and their respective compound time signatures such as 6 9 8, 8, 12 etc. 8', 116::int),
    ('MUS 001', 12, '11', 'Types and Qualities of Intervals and Triads/Chords', 'Major, Minor, Augmented and Diminished Intervals and Triads/Chords.', 'To understand basic intervals such as major, minor, perfect, augmented and diminished. Altered, borrowed and alternate triads/chords.', 116::int),
    ('MUS 001', 13, '12', 'Terms, Signs and Abbreviations', 'Musical Terms, Signs and Abbreviations.', 'To understand musical terms, signs and abbreviations that denote varying tempos, dynamics, expression of moods and articulations, ornaments', 116::int),
    ('MUS 001', 14, NULL, NULL, NULL, '(appoggiatura, acciaccatura, mordents, trills etc.) and other embellishments', 117::int),
    ('MUS 001', 15, '13', 'Basic Applied Music I', 'Drills in Basic Techniques of the Piano/Voice/Any other Western Instruments', 'Technical exercises should include four keys up to three sharps and flats.', 117::int),
    ('MUS 001', 16, NULL, NULL, 'Technical Exercises Including Scales and Arpeggios on the student’s preferred musical Instrument (Voice inclusive)', 'To perform musical pieces in C Major, G Major, D Major, A Major and their relative minor keys.', 117::int),
    ('MUS 001', 17, NULL, NULL, 'Selected Pieces or works', 'Musical pieces of varying dynamics, keys, that require technical abilities would be performed.', 117::int),
    ('MUS 002', 1, '1', 'Definitions, Characteristics, Sources and Importance of African Music.', 'Introduction to African Music; Definitions of African Music and its Relationship to Folk Music. Characteristics of African Music. Elements used within the Music. Introduce Traditional Music ‘Festival and Ceremony’.', 'Meaning of African music in relation to belief, ethics, tradition, ideologies, socio-cultural identities etc. Sources and significance of music in African culture.', 118::int),
    ('MUS 002', 2, '2', 'A Survey of the Uses and Functions of Music among the People of Africa.', 'The Roles of Music in African Societies. Music Styles used for different Events or Occasions. Music in Festivals and Religious Activities.', 'Socio-cultural usages of African music.', 118::int),
    ('MUS 002', 3, '3', 'Vocal Forms in African Music.', 'Vocal Forms in both Traditional and Contemporary African Songs.', 'Call and Response; Antiphony; Declamation; Strophic; Cantor and Chorus; Complementary Duet etc.', 118::int),
    ('MUS 002', 4, '4', 'Dance in African Music', 'The Types and Importance/Significance of Dance in African Music. The Relevance of Dance in the African Society', 'Introduction to African Dance; Elements used within the dance such as Style, Choreography, Rhythm, Movement, etc.; Relationship between Music and Dance; Dance using Basic Movement and', 118::int),
    ('MUS 002', 5, NULL, NULL, NULL, 'Rhythm; Dance in Festivals; Functions of Dance in African Society', 119::int),
    ('MUS 002', 6, '5', 'Theory of African Music', 'The Concept of Scale, Melody, Harmony and Rhythm in African Music. Types of Scales in African Music.', 'Derivation of pentatonic, hexatonic, heptatonic, diatonic and other scales must be examined. Simple harmonic progressions and rhythmic movements in African music.', 119::int),
    ('MUS 002', 7, '6', 'Popular Music in Africa', 'Definition of African Popular Music. Types of Popular Music Genres in Africa. Exponents of Popular Music in Nigeria.', 'To examine various genres of Popular music in Africa such as ikwokirikwo, afrobeats, juju, fuji, reggae, highlife, apala etc. and their exponents/ practitioners, such as Fela, Ebenezer Obey, Sikiru Ayinde Barrister, Majek Fashek, Osita Osadebey, Ayinla Omowura.', 119::int),
    ('MUS 002', 8, '7', 'Art Music in Africa', 'The Concepts, Composers and Practice of African Art Music.', 'Definition of African Art Music; Exponents of Art Music in Nigeria: Laz Ekwueme, Ayo Bankole, Fela Sowande, Adams Fiberisima, Paul', 119::int),
    ('MUS 002', 9, NULL, NULL, NULL, 'Harcourt Whyte, Akin Euba, Joshua Uzoigwe, Nketia and Meki Nzewi, etc.', 120::int),
    ('MUS 002', 10, '8', 'African Music Instruments and their Ensembles.', 'Classifications of African Musical Instruments; Functions of African Musical Instruments.', 'Curt Sachs principles of universal classification of musical instruments. Idiophones, membranophones, chordophones and aerophones etc. Ensembles such as Dundun, Bata, Gbandikan, Gbedu, Kanlangu, Ukom, Mbira, etc.', 120::int),
    ('MUS 003', 1, '1', 'Intervals', 'Further Notation of Basic Intervals, Triads (Major and Minor) on the Staff.', '1. The students should be taught on how to identify and notate simple melodic tunes. This is both a teaching and practical session. Hence, students are expected to be taught on the basics of distinguishing tones, Rhythmic identification and Harmonic appreciation.
2. Students should be able to identify perceived sounds and be able to notate them appropriately.
3. The art of sight-reading simple melodic tunes and harmonic tunes', 121::int),
    ('MUS 003', 2, '2', 'Melody', 'Aural Drill on Melody', NULL, 121::int),
    ('MUS 003', 3, '3', 'Harmony', 'Aural Drill on Harmony', NULL, 121::int),
    ('MUS 003', 4, '4', 'Rhythm', 'Aural Drill on Rhythm', NULL, 121::int),
    ('MUS 003', 5, '5', 'Sight-Reading', 'Basic Techniques of Reading/Playing from Scores through Simple Rhythms and Musical Notation', NULL, 121::int),
    ('MUS 003', 6, '6', 'Basic Applied Music II', 'Drills in Basic Techniques of playing African musical Instruments or other Western musical instruments.', 'Technical exercises should include four keys up to three sharps and flats.', 121::int),
    ('MUS 003', 7, NULL, NULL, 'Carry out technical exercises in the demonstration of African musical instruments.', 'To perform musical pieces in the category of traditional/contemporary African music.', 121::int),
    ('MUS 003', 8, NULL, NULL, 'Selected African musical Pieces or works', 'African musical pieces of varying dynamics and keys that require technical abilities would be performed.', 122::int),
    ('MUS 004', 1, '1', 'Definition of Music as Art and Science', 'Defining Music in relation to the disciplines in the fields of Arts and Sciences.', 'Relating structure to Arts; and sound to Science.', 122::int),
    ('MUS 004', 2, '2', 'Sound', 'Definition of Sound, its Properties and artistic implications.', 'Aural perception of sound, intensity, pitch, timbre, duration etc.', 122::int),
    ('MUS 004', 3, '3', 'Art of Listening', 'The Art of Listening, Types of Listening, Basic Listening Skills.', 'Appreciation of music through active, passive,', 122::int),
    ('MUS 004', 4, NULL, NULL, NULL, 'critical, emphatic, and selective listening.', 123::int),
    ('MUS 004', 5, '4', 'The Elements and Basic Structures of Music.', 'Forms in Music – Binary Form, Ternary Form, Rondo form, Variation Form, Strophic Form, Sonata Form, Imitative Form, Composite Form, etc.', 'Elements such as melody, rhythm, harmony, instrumentation, styles, dynamics, tempos etc. Various sections in all forms of music in Western and African cultures.', 123::int),
    ('MUS 004', 6, '5', 'Eras and Composers of Western Classical Music.', 'Music in Antiquity, Middle Ages, Renaissance Period, Baroque Period, Classical Period, Romantic Period, 20th Century.', 'Sociological traits, names and biographies of Western classical music composers. Application of Musical Elements in the Works of each Period.', 123::int),
    ('MUS 004', 7, '6', 'Appreciation of Music in Africa and other World Cultures.', 'Popular Music in Africa – Juju, Highlife, Ikwokirikwo, Swange, Fuji, Afrobeat. Popular Music of other World Cultures, Reggae, Calypso, Rhumba, Jazz etc.', 'Appreciation of traditional and contemporary music in Africa and other World cultures.', 123::int),
    ('VSA 001', 1, '1', 'O rigin of Art and the Prehistoric Periods', 'Cave art, Prehistoric Periods, Paleolithic, Mesolithic and Neolithic periods', 'A general survey course that would deal with an introduction to European and African Art- Art of the renaissance period, various artistic movements, cubism, expressionism, post modernism, modernism, impressionism etc. A general introduction to the arts of Africa- brief studies of selected African and European artists and movements. A short assessment of various artistic movements, heritage sites, museums, monuments and art workshops in Africa.', 128::int),
    ('VSA 001', 2, '2', 'N ubian, Egyptian, Greek and Roman Arts', 'Characteristics of Nubian and Egyptian, Greek and Roman Arts Medium, Characteristics and Functions.', NULL, 128::int),
    ('VSA 001', 3, '3', 'A rt Movement', 'Renaissance Art of Europe, Abstract Expressionism, Surrealism, Cubism, Abstraction, Pop Art, Minimal Art, Negritude, Natural Synthesis, Ulism and Onaism Conceptual Art, Expressionism Issue- based art and globalization', NULL, 128::int),
    ('VSA 001', 4, '4', 'A frican Art of the Sub-Saharan Region', 'Masking traditions, Classical sculptures from Nigeria, Nok, Igbo-Ukwu, Ife, Benin, Tsoede, Owo, and such other artistic traditions', NULL, 128::int),
    ('VSA 001', 5, '5', 'A rt Personalities in Nigeria and Across the Globe', 'Pablo Picasso, Paul Cezanne, Michelangelo Bounarroti, Bruce Onobrakpeya, Yussuf Grillo, Malangatana Valente, David Koloane, El Salahi, Skunder Boghosian, Sokari Doughlas Camp, Yinka Shonibare, Aina Onabolu, Akin Lasekan, Ben Enwonwu, Uche Okeke, Demas Nwoko, Clara Ugbodaga Ngu, Ladi Kwali, Kolade Oshinowo, Jimoh Buraimoh, Nike Davies-Okundaye, Victor Ekpu, Pat Oyelola, Jelili Atiku, Jerry Buhari, Abayomi Barbar, Dele Jegede, Akin Onipede, Sola Ogunfunwa, John Adenle, Sola Ogunfuwa, Joseph Azi, El-Anatsui, Adams Ohams, Erabor Emokpae, Taiwo Olaniyi, Bruce Onobrakpeya, Adagogo Green, Billy Rose, Amaize Ojekere, Kunle Adeyemi, Ebun Aleshinloye, Adams Ohams, Jimoh Ganiyu, Sunmi Smart Cole, and such other art Personalities,', 'Identification of selected art works and art personalities across the globe and their specializations.', 129::int),
    ('VSA 001', 6, '6', 'M ajor museums, galleries, art workshops and historical sites in Nigeria', 'Federal, states and private museums, art galleries, art workshops and historical sites', 'A short assessment of various artistic heritage sites, museums, monuments and art workshops in Africa.', 129::int),
    ('VSA 002', 1, '1', 'Painting', 'Nature: Landscape and Seascape Figure Studies and Portraiture Still- life Imaginative Composition.', 'The course provides an overview of the entire range of courses categorized as two-dimensional art. For these range of topics, candidates will be introduced to various aspects of the theory, materials and methods. These include Painting, Drawing, Textile, Graphics, Photography, Print making and Digital Art. Practical tasks and assignments are also to be carried out.', 130::int),
    ('VSA 002', 2, '2', 'Drawing', 'Understanding the elements and principles of drawing. Nature drawing, still life, life drawing and imaginative composition.', NULL, 130::int),
    ('VSA 002', 3, '3', 'Textile', 'Tools and materials associated with basic textiles production. Principles and elements of textile design e,g Use of colour, shapes, lines. Basic textile design; repeat patterns. Practical exercises in selected areas such as textiles design, fabric resist, dyeing using various methods which involve starch resist and wax, printing and painting, stitching, folding, pleating. Fashion design and accessories for body adornment, costume and set design. Socio-cultural significance of cloth in Africa. Textile traditions in Africa such as: Nigeria – Aso ofi: Sanyan, Etu, Kijipa, Akwete, Ghana -Adinkra. Kente,', NULL, 130::int),
    ('VSA 002', 4, NULL, NULL, 'Mali - Kanga and Mud cloth. Selected textile production centres such as horizontal and vertical loom weaving in southwestern e.g Yoruba, Ebira, Nupe, Igbo. Cloth dyeing Centre in Itoku-Abeokuta, Akerele-, Lagos, Ijumu-Kogi, Osogbo and Kano.', NULL, 131::int),
    ('VSA 002', 5, '4', 'Graphics/ Photography/ Printmaking', '• Graphic design, • Cartoon illustration • Printmaking methods • Photography: techniques, the camera.', NULL, 131::int),
    ('VSA 002', 6, '5', 'Digital Art', '• Digital posters, editorial graphics, info-graphics, website design, digital marketing and sales of artworks, digital illustration, Artificial Intelligence, software packages and applications.', NULL, 131::int),
    ('VSA 003', 1, '1', 'Ceramics', 'Methods of using clay for hand built- slab, coil, pinching methods, Casting- press and slip casting Wheel throwing techniques. Drying and firing. Use of slip and oxides for decorating and painting. Glazing and firing techniques.', 'This course is an introduction to three-dimensional art forms such as ceramics and sculpture. Candidates will be taught the various materials and methods of Ceramics and Sculpture. They also learn the terminologies and take part in the production of selected practical assignments.', 132::int),
    ('VSA 003', 2, '2', 'Sculpture', 'Materials and methods in sculpture Modeling simple forms and relief sculpture Studies in sculpture in the round Casting techniques in sculpture Metal assemblage Installation art.', NULL, 132::int),
    ('VSA 004', 1, '1', 'Recycle Art and Craft', 'materials and methods in jewelry making, bead stringing, wirework, basket weaving, wood carving, papier mache art, macrame', 'Candidates would be taught the methods and materials in simple jewelry production and casting. An exploration of indigenous art and craft traditions as well as recycling art. There will be one practical project.', 133::int),
    ('VSA 004', 2, '2', 'Simple Casting Techniques', 'Simple casting procedures, cire perdue, centrifugal casting, sandcasting techniques.', NULL, 133::int),
    ('VSA 004', 3, '3', 'Indigenous Materials, tools and equipment for Art and Craft”', 'Stones, bones, shells, cowries, sourced or found object, buttons, paper and fabrics', NULL, 133::int),
    ('YOR 001', 1, '1', 'Yorùbá Speech Sounds', 'i) Consonants ii) Vowels', 'Practice exercises on the following will facilitate understanding topics covered in this course
1. The four parameters of classifying consonants:
- Place of articulation, Manner of articulation -State of the glottis, -What operates in the nasal cavity
2. The three parameters of describing vowels:
-Position of tongue involved -Height of tongue -Shape of the lip -Nasal or oral quality V-syllable: a-dé è-rò', 137::int),
    ('YOR 001', 2, '2', 'Syllable Structure Types', 'i) V = vowel ii) CV = consonant-vowel iii) N = syllabic nasal', NULL, 137::int),
    ('YOR 001', 3, '3', 'Phonological Processes', 'Types of Phonological Processes in Yorùbá: i) Vowel Harmony ii) Assimilation iii) Deletion iv) Coalescence', NULL, 137::int),
    ('YOR 001', 4, '4', 'Introduction to Linguistics', 'i) definition, aims and scope of linguistics-', NULL, 137::int),
    ('YOR 001', 5, NULL, NULL, 'Language teaching and learning, Translation ii) -processes of book publishing iii) animal language;', 'CV- syllable: kà, sá N-syllabic nasal:
Description of language structure, use, and aquisition; Documentation and preservation of language ; 5 Branches of linguistics:
phonetics, phonology, morphology, syntax and semantics Language skills – listening, speaking, reading and writing Different types of Translation:
Interlingual Translation, Literary translation, Non-literary translation
- machine translation and interpretation
- relationship between language and society;
- language change over time, genetic relationship among languages Forms of animal language;', 138::int),
    ('YOR 001', 6, NULL, NULL, NULL, 'animal language versus human language;', 139::int),
    ('YOR 001', 7, '5', 'Advanced Comprehension and Composition', 'i) Yorùbá orthography ii) Composition iii) Different types of composition-iv) History of the development of Yorùbá language to date. v) Comprehension, Speech making and Summary', '- Tonal marks, syllable structure, word separation,
- Comparison between old and modern orthography, spelling, punctuation.
- organizational pattern, features of a good composition- introduction, body and conclusion.
- Narrative. Explanatory. Argumentative essays, etc. Dialogue and letter writing, etc. From Colonial period to Modern day Different types of Comprehension – prose, dialogue and poetry Thematic, Descriptive', 139::int),
    ('YOR 002', 1, '1', 'Definition and classification of Oral Yorùbá Literature:', 'Body of cultural knowledge, stories and traditions that are transmitted from generation to generation (prose, drama and poetry)', 'Practice exercises in and out of the lecture room on the following will facilitate understanding topics covered in this course. Oral and written literature in different sub areas of prose, drama and poetry. Eégún Alárìnjo Ọdún ìbílè ̣ Oríṣìíríṣìí ijó', 140::int),
    ('YOR 002', 2, '2', 'Prose: Yorùbá folklores', 'i) Àló ̣onítàn ii) Ìtándòwe iii) Ìtàn ìwásẹ̀ ̣ iv) Ìtàn akọni', NULL, 140::int),
    ('YOR 002', 3, '3', 'Drama:', 'Yorùbá traditional drama:', NULL, 140::int),
    ('YOR 002', 4, '4', 'Poetry', 'Àrángbo ̣– Recitation speech mode', '-Òwe, Àló ̣àpamò,̣ Oríkì-Orílè ̣', 140::int),
    ('YOR 002', 5, NULL, NULL, 'Ìsàré- Chant mode, Orin-Song mode,', '(Panegyrics), Àrò,̣ Ìmó,̣ Oríkì-Orílè.̣.
- Ẹsẹ Ifá, Ìjálá
iii) Iwì Egúngún/Èṣ̣ à pípè Ẹkún Ìyàwó Oríṣìíríṣìí orin Oríṣìíríṣìí ìlù, Orin ìbílè ̣', 141::int),
    ('YOR 003', 1, '1', 'Yorùbá Lexical and non-lexical Categories', 'i) Nouns ii) Verbs iii) Adjectives iv) Preposition v) pronouns, vi) cojunctions', 'Practice exercises in and out of the lecture room on the following will facilitate understanding topics covered in this course Components of words. Division into:
1. Lexical categories
2. Non-lexical categories', 141::int),
    ('YOR 003', 2, '2', 'Formation of Phrases from Different Categories', 'i) Noun Phrase ii) Verb Phrase iii) Adjective Phrase iv) Preposition Phrase', NULL, 141::int),
    ('YOR 003', 3, '3', 'Classification of Sentences', 'i) Structural classification -Simple -Compound -Complex ii) Functional classification -Declarative -Interrogative -Imperative -Exclamation', '3. Definition of each category
1. Definition of each phonological processes
2. Description of each phonological processes', 142::int),
    ('YOR 003', 4, '4', 'Word Formation Acculturation of loan words to Yorùbá', 'Affixation, Duplication, and Compounding i) Languages from where word are loaned ii) Channels of loaning words iii) Visual mechanism of loaning iv) Perceptual mechanism of loaning', NULL, 142::int),
    ('YOR 004', 1, '1', 'Definition and classification of Written Yorùbá Literature', 'Body of literary work recorded in written form- prose, drama and poetry,', 'Practice exercises in and out of the lecture room on written literature in the following subsections will facilitate topics covered in this course:
Narrative techniques; Characterization; Themes; and Yorùbá cultural norms and values', 143::int),
    ('YOR 004', 2, '2', 'Elements of written Yorùbá Literature', 'Prose i) Plot ii) Setting iii) Characters iv) Themes v) Language', NULL, 143::int),
    ('YOR 004', 3, NULL, NULL, 'Drama i) Plot ii) Setting iii) Dialogue iv) Themes v) Language', NULL, 143::int),
    ('YOR 004', 4, NULL, NULL, 'Poetry i) Form and structure ii) Rhythm and sound iii) Language iv) Themes v) Figures of speech', NULL, 144::int),
    ('YOR 004', 5, NULL, NULL, NULL, 'i) Reverend Samuel Àjàyí Crowther
ii) Reverend Henry Townsend
iii) Reverend David Hinderer
i) Ìwé Ìròyín fún àwọn Ẹ̀g̣ bá àti Yorùbá
ii) Akéde Èkó
iii) Lagos Weekly records Ẹgbe ̣Àgbà-ò-tán, Ẹgbe ̣Ako ṃ ọlédè Yorùbá, Ẹgbe ̣Onímọ̀ ̣Èdè Yorùbá', 144::int),
    ('YOR 004', 6, '3', 'Roles of the Missionaries, early Newspapers and Cultural Groups in the development of Written Yorùbá Literature', NULL, NULL, 144::int),
    ('YOR 004', 7, NULL, NULL, 'Missionaries Early Newspapers Cultural Groups', NULL, 144::int),
    ('ACC 001', 1, '1', 'Introduction to Accounting', 'Nature of accounting; Distinction between Book-keeping and Financial Accounting.', 'Definition of Accounting, similarities and differences between book-keeping and accounting. Role of accounting in economic decision making.', 149::int),
    ('ACC 001', 2, NULL, NULL, 'Importance of financial accounting and users of financial accounting information.', 'Users of financial accounting information and their needs; (managers, current and potential investors, employees, financial institutions, financial analyst,', 149::int),
    ('ACC 001', 3, NULL, NULL, 'Types of profit making organisations and types of not-for-profit organisations.', 'Government agencies, researchers, etc. Sole proprietorships, partnerships, limited liability companies, religious bodies, political parties, trade associations, non-governmental organisations, etc.).', 150::int),
    ('ACC 001', 4, NULL, NULL, 'Fundamental Accounting Concepts; Accounting Equations; Business Transactions and their impacts on Accounting Equations.', 'Accounting Concepts: Entity, duality, going concern, objectivity, matching, prudence, realisation, accrual, historical, money measurement, fairness, substance over form, materiality, etc', 150::int),
    ('ACC 001', 5, NULL, NULL, 'Analysis of transactions in the context of accounting equations.', 'Basic accounting equation: Assets = Capital + Liabilities. Components of basic accounting equation and their manipulations.', 150::int),
    ('ACC 001', 6, NULL, NULL, 'Basis of Accounting.', 'Impact of business transactions on accounting equation. Payments for goods and services, acquisition of non-current assets, income, part payments for assets acquired, etc. Accrual and cash basis of Accounting', 150::int),
    ('ACC 001', 7, '2', 'Introduction to the Evolution of Accounting Standard Bodies and IASB Conceptual Framework', 'NASB, FRCN, IASB, and IFRS Foundation. Definition, scope and objectives of conceptual framework.', 'Brief introduction to NASB, functions of the FRCN, History, structure and functions of the International Accounting Standards Board (IASB):
The IFRS foundation, IFRS Interpretation Committee, IFRS Advisory Council and Directorate of Technical Activities and the Technical Staff. Definition of conceptual framework, objective of general', 150::int),
    ('ACC 001', 8, NULL, NULL, NULL, 'purpose financial reporting, qualitative characteristics of useful financial information, financial statements and the reporting entity and the elements of financial statement.', 151::int),
    ('ACC 001', 9, '3', 'Introduction to some International Accounting Standards (IAS)', 'IAS 1/IFRS 18, (Presentation of Financial Statements/Presentation and disclosure in Financial Statement), IAS 2 (Inventories) and IAS16 (Property, Plant and Equipment).', 'IAS 1/IFRS 18 - preparation of financial statements/ Presentation and disclosure in Financial Statement. IAS 2 Inventories: Recognition and measurement of inventory, methods of valuation of inventory using FIFO and Weighted Average. IAS 16: (a) Identification of the elements of PPE cost.
(b) Measurement of PPE cost
(c) Depreciation for PPE
(d) Accounting for disposal of PPE', 151::int),
    ('ACC 001', 10, '4', 'Basic Steps involved in Book-Keeping up to the Trial Balance', 'Source Documents: information contained in the source documents, subsidiary books, the principal books of accounts, i.e., Ledgers. Types of Accounts / Classification of Accounts.', 'Definition of source documents, recording of transactions into source documents, importance of source documents, types of source documents (receipts, invoices, vouchers, debit notes, credit notes, paying-in-slips/bank tellers, cheques and cheque stubs, dividend warrants, etc.). Importance of subsidiary books, types of subsidiary books:
purchases day book, sales day book, sales returns day book/return inwards day book, purchases returns day book/return outwards day book, journal proper/general journal/principal journal, and cash book: single', 151::int),
    ('ACC 001', 11, NULL, NULL, NULL, 'column cash book, double column cash book, three column cash book and petty cash book and the dual purpose of cash book. Uses of general journal: opening entries, closing entries, determination of capital, and correction of errors, inter accounts transfers, etc. Types of ledgers:
Sales/Receivables Ledger, Purchases/Payable Ledger, Cash Book. The general ledger: income, expenses, assets, liabilities and capital of the organisation. Nominal accounts, e.g., sales, expenses, drawings, capital accounts. Personal accounts e.g. receivables and payables accounts. Real accounts, e.g., non-current assets i.e. tangible and intangible, cash and bank, and inventory.', 152::int),
    ('ACC 001', 12, '5', 'Debit and Credit Entries in Accounting', 'Principles of Double Entries', 'The meaning of debit and credit entries in financial accounting. Analysis of transactions before posting. What to debit, what to credit. Elements of financial statements (i.e. assets, expenses, capital, revenue and liabilities) and how they affect the debit and credit entries. Balancing of ledger accounts. Preparation of Trial Balance to ascertain the arithmetical accuracy of the entries in the ledger accounts.', 152::int),
    ('ACC 001', 13, '6', 'Accounting Errors and Corrections', 'Limitations of the Trial Balance', 'Errors not affecting the trial balance: errors of principles, complete omission of transaction, original entry, commission, complete reversal of entries, compensating error. Errors affecting the agreement of the Trial Balance/tracing the sources of errors: casting error, transposition, failure to pick a ledger balance, single entry error, and wrong classification of a ledger balance in the trial balance.', 153::int),
    ('ACC 001', 14, NULL, NULL, 'Suspense Account', 'Correction of errors: Use of suspense account, identifying errors to be corrected through the suspense account, and other errors not affecting the suspense account.', 153::int),
    ('ACC 001', 15, NULL, NULL, 'Control Account', 'Control accounts and self-balancing ledgers. General use of control accounts: trade receivable control accounts and trade payable control accounts.', 153::int),
    ('ACC 001', 16, '7', 'Bank Reconciliation Statement', 'Balance as per business cash book: Balance as per bank statements.', 'Causes of differences between balance in the bank statement and the balance in the cash book. Transactions recorded only in the cash book and transactions recorded only in the bank statements. Errors made in the cash book and the bank statement. Purpose of bank reconciliation. Framework for bank reconciliation statement. Preparation of adjusted cash book using legitimate items affecting the business and bank reconciliation statement.', 153::int),
    ('ACC 001', 17, NULL, NULL, NULL, 'Identification of items affecting the preparation of bank reconciliation statements only.', 154::int),
    ('ACC 001', 18, '8', 'End of Period Adjustments', 'The periodicity concept; matching concept, capital expenditure, revenue expenditure, depreciation, allowances.', 'Explanation of the linkage among the concepts of going concern, periodicity and matching in the preparation of financial statements to assess business performance. Definitions of capital expenditure and revenue expenditure. Accruals (expenses and income), Prepayments (expenses and income), Depreciation of non-current assets: e.g., straight line and reducing balance methods, adjustments for disposal of non-current assets. Allowances for irrecoverable and doubtful debts and treatment of bad debt recovered. Allowances for discount allowed.', 154::int),
    ('ACC 001', 19, NULL, NULL, 'Revised Trial Balance', 'Treatment of post-trial balance adjustment/end of period adjustment: preparation of revised trial balance.', 154::int),
    ('ACC 001', 20, '9', 'Financial Statements of Sole Proprietorship', 'Preparation of Financial Statements of Sole Proprietorship', 'The Income Statement:
determination of gross profit and net profit.', 154::int),
    ('ACC 001', 21, '10', 'Manufacturing Accounts', 'Manufacturing Accounts', 'Determination of cost of goods manufactured: Prime cost, Factory overheads, Total cost of goods manufactured, Adjustments for work-in-progress and cost of goods manufactured, Direct purchase of finished goods.', 154::int),
    ('ACC 001', 22, NULL, NULL, NULL, 'Treatment of unrealised profit elements from unsold inventory where manufactured goods are transferred to the sales department at a profit.', 155::int),
    ('ACC 001', 23, '11', 'Partnership Accounts', 'Introduction to Partnership Accounts.', 'Formation of Partnership including Partnership Deed, The Partnership Act 1890, Types of partnership (limited and unlimited), Types of partners (active and dormant), Statement of Profit or Loss, Statement of Distribution of Profits, Current Account and Capital Account, Preparation of Statement of Financial Position. Preparation of Financial Statements in the absence of Partnership Agreements.', 155::int),
    ('ACC 001', 24, '12', 'Incomplete Records', 'Preparation of Financial Statements from Incomplete Records', 'Single entry book keeping:
Preparation of Opening Statement of Affairs, Determination of sales and purchases, Determination of cash and other expenses, Preparation of Income Statement and Statement of Financial Position.', 155::int),
    ('ACC 001', 25, '13', 'Accounts of Clubs and Societies', 'Preparation of Financial Statements of Not-for-Profit Organisation', 'Preparation of statements of income and expenditure to determine surplus or deficit for the period. Preparation of trading account where the club or society engages in other business activities such as restaurant, bar, etc. Preparation of receipts and', 155::int),
    ('ACC 001', 26, NULL, NULL, NULL, 'payments account. Preparation of statement of affairs.', 156::int),
    ('ACC 001', 27, '14', 'Financial Statements of Limited Liability Companies', 'Introduction to the Preparation of Financial Statements of Limited Liability Companies', 'Types of limited liability companies, difference between limited liability companies and other forms of business, articles and memorandum of association, shareholders and directors of companies, issue of shares and debentures, Preparation of statement of profit or loss and other comprehensive income for internal use. Preparation of statement of financial position for internal use.', 156::int),
    ('ACC 002', 1, '1', 'Introduction to Cost and Management Accounting', 'Nature and Scope of Cost Accounting; Management Accounting; Comparison of Cost and Management Accounting with Financial Accounting and organisation of cost accounting department and its relationship with other departments', 'Definition of Cost Accounting, objectives of Cost Accounting, qualities of Cost Accounting information, importance of cost accounting information to the management, differences between cost accounting and financial accounting, differences between cost accounting and management accounting. Difference between costing methods and costing techniques. Organogram of cost accounting department showing its relationship with other departments.', 157::int),
    ('ACC 002', 2, '2', 'Basic Elements of Cost', 'Introduction to Cost Terminologies and Meanings; Components of Cost; Cost Classification and Behaviour; Cost Estimation Technique.', 'Meaning of cost, cost centres and cost units, cost objects, cost allocation, cost apportionment, cost allowance and coding. Classification of cost according to: elements (material, labour and expenses), traceability (direct and indirect costs), behaviour (variable, fixed, stepped fixed and mixed costs), function (production, administration, selling and distribution, research and development costs) and relevance (relevant and irrelevant costs). Other classifications:
controllable and uncontrollable costs, product and period cost, avoidable cost, sunk cost, discretionary cost and opportunity cost.', 157::int),
    ('ACC 002', 3, NULL, NULL, NULL, 'Cost estimation using high and low method of separating a mixed cost only.', 158::int),
    ('ACC 002', 4, '3', 'Material Costing', 'Purchasing, Receipt, Storage and Issuance of Materials.', 'Store and store keeping, purpose of the store keeping, store layout, types of store (centralised store, decentralised stores, combination of both), and factors that facilitate effective materials cost control. The purchasing process (material requisition form, purchase requisition form, purchase order form, receiving inventory into the store, delivery note, goods received note, and payment to suppliers). Recording inventory levels: (the bin card and the store ledger card/account). Stock taking: periodic stock taking and continuous stock taking.', 158::int),
    ('ACC 002', 5, '4', 'Quantitative Model for Material and Stock Controls', 'Identification of Costs of Inventory; Control of Inventory; Efficiency in Managing Material Costs; Valuation of Inventory.', 'Inventory costs, i.e. (purchase cost, ordering cost, holding cost and stock out cost and their components). Inventory Control Levels: re-order level, maximum inventory level, minimum inventory level, and average inventory level. Economic Order Level (EOQ) including its assumptions and calculation of total inventory cost. Inventory Valuation: Pricing of issues and valuation of inventories, methods of pricing issues and valuing inventories such as: FIFO, LIFO and Weighted Average Methods.', 159::int),
    ('ACC 002', 6, '5', 'Labour Costing', 'Introduction to Labour Costing and Control; Labour Remuneration Methods', 'Labour behaviour and control, job evaluation, merit rating, work study, labour cost computation including over time components. Time Rate methods of remuneration: Piece Rate methods of remuneration (Straight piece rate, Differential piece rate; and Piece rate with guaranteed minimum wage); Premium bonus schemes such as:
Halsey bonus scheme, Halsey Weir bonus scheme and Rowan bonus scheme. Determination of Direct and indirect elements of cost of labour.', 159::int),
    ('ACC 002', 7, '6', 'Overhead Cost', 'Accounting for Overheads', 'Definition of overheads, features and accumulation of overheads. Stages of absorbing overheads: allocation, apportionment, re-apportionment: (one step, elimination, and reciprocal methods) and absorption of overheads. Bases of overhead absorption rate:
direct labour hours, machine hours, production units, percentages of labour cost, material cost, and prime cost. Calculation of over and under absorption of overheads.', 160::int),
    ('ACC 002', 8, '7', 'Costing Methods', 'Job Costing', 'Features of job costing. Examples of jobs and preparation of job cost sheet. Content of job cost sheet: material cost and wages/labour costs. Overhead cost: allocation, apportionment and absorption of overhead cost into jobs. Computation of mark-up and margin.', 160::int),
    ('ACC 002', 9, NULL, NULL, 'Process Costing', 'Introduction to process costing, Calculation of normal, abnormal loss and abnormal gain and preparation of a single process account in line with IAS 2.', 160::int),
    ('ACC 002', 10, '8', 'Cost Book Keeping', 'Integrated Accounting System and interlocking Accounting System and profit reconciliation', 'Definition and types of Accounting system; integrated and interlocking accounting system, posting to cost ledgers and cost ledger control account, extraction of trial balance and reconciliation of profit', 160::int),
    ('ACC 002', 11, '9', 'Costing Techniques', 'Absorption Costing Technique; Marginal Costing Technique.', 'Definitions of absorption and marginal costing. Differences between absorption and marginal costing techniques. Computation of business performance using marginal costing and absorption costing techniques. Reconciliation of Absorption costing profits and Marginal Costing profits. Application of costing techniques in economic decision making.', 161::int),
    ('ACC 002', 12, NULL, NULL, 'Standard Costing', 'Definition of standard costing, purposes and advantages, types of performance standard: basic, ideal, expected and current standards, computation of basic variances:
material, price and usage variances; labour rate and efficiency variances; variable overheads expenditure and efficiency; fixed overhead expenditure and volume variances.', 161::int),
    ('ACC 002', 13, '10', 'Cost Volume Profit Analysis', 'Introduction to Cost Volume Profit Analysis', 'Features of cost volume profit analysis. Assumption of Break Even Analysis. Application of Break Even Analysis. Contribution Margin Ratio, margin of safety, graphical analysis, break even chart, contribution chart, profit volume chart graph and limitation of break-even analysis.', 161::int),
    ('ACC 002', 14, '11', 'Budgeting', 'Introduction to Budgeting; Cash Budgets.', 'Definition of budget, fundamentals of budgeting, limiting factors on budget, benefits of budget, types of budget and budgeting process. Preparation of', 161::int),
    ('ACC 002', 15, NULL, NULL, NULL, 'functional budget simple cash budget without discount.', 162::int),
    ('ACC 003', 1, '1', 'History of Auditing', 'Introduction to Auditing', 'Scope and Development of Accounting:
Stewardship Scope, Financial Accounting Scope, Management Accounting Scope, Social Welfare Accounting Scope. Development of Professional Accounting Bodies and Branches of Accounting. Features of modern business: separation of owners from management. Information asymmetry emanating from Stewardship Accounting. Need for external attestation of management financial reports – Auditor’s attestation.', 162::int),
    ('ACC 003', 2, '2', 'Nature and Scope of Auditing', 'Meaning of Auditing', 'Definition, nature and types of audit. Importance of Auditing.', 163::int),
    ('ACC 003', 3, '3', 'Non Audit Services', 'Spin-off effects of Auditing', 'Some of the Spin-off effect of auditing:
accounting services, consultancy, executorship, feasibility report, staff audit, etc.', 163::int),
    ('ACC 003', 4, '4', 'Audit Framework', 'Legal/Statutory Framework; Conceptual Framework; Regulatory Framework.', 'Legal Framework (CAMA 2020), for Auditing in Nigeria: Qualification (who may be an auditor), Appointment, Removal, Duties and Rights. Auditing Guidelines and Standards. Qualities expected of auditors. Concepts of audit independence, objectivity, integrity, confidentiality, due care, and competence.', 163::int),
    ('ACC 003', 5, '5', 'Audit Communication', 'Documentation of Audit-Client Agreement and Findings', 'Audit Communication: Letter of Engagement, Letter of Representation, Letter of Weakness, audit working papers and access to statutory corporate documents.', 163::int),
    ('ACC 003', 6, '6', 'Report', 'Audit Report', 'Audit Report: Concept of True and Fair View (Fair Presentation), types of audit reports and Contents of Audit Report.', 163::int),
    ('ACC 003', 7, '7', 'Contemporary issues', 'Relevant Issues in Accounting and Auditing', 'Definition and Nature of Creative Accounting. Definition and Nature of Forensic Accounting. Ethics in Accounting, Ethics in Auditing.', 163::int),
    ('ACC 004', 1, '1', 'History of Tax', 'History of Tax and Taxation in Nigeria', 'Definition of Tax, difference between tax and taxation, brief history of Tax and Taxation in Nigeria. Canons of taxation: simplicity, convenience, certainty and equality.', 164::int),
    ('ACC 004', 2, '2', 'Tax Administration in Nigeria', 'Tax authorities in Nigeria: Federal Government; (refer to the Nigeria Revenue Service (Establishment) Act, 2025. – Sections 3, 4, 6, 7, 8, 9, 14, 15 & 18). Joint Revenue Board of Nigeria (Establishment) Act, 2025 – Sections 3, 4, 5, 6, 23, 24, 25 & 26. State Government: Nigeria Tax Administration Act, 2025 Sections 87, 88, 89, 90, 91, 92.', 'Federal: Establishment, composition, quorum and functions of: Nigeria Revenue Service Board, formerly known as Federal Inland Revenue Board, Technical Committee, Joint Revenue Board and Tax Appeal Tribunal. Nigeria Revenue Service, formerly known as Federal Inland Revenue Service and Tax Appeal Commissioners. State: Establishment, composition, quorum and functions of the Management Board of the State Service formerly known as State', 164::int),
    ('ACC 004', 3, NULL, NULL, 'Local Government: Nigeria Tax Administration Act, 2025. Sections 93, 94, 95 & 96 Assessment and Filing of Returns', 'Board of Internal Revenue and Technical Committee. Local Government: Establishment, composition, quorum and functions of the Local Government Revenue Committee. Assessment – Notice of assessment, types of assessment (original assessment, additional and revised assessment), forms (provisional and self assessment) of assessment. Returns – Documents to be submitted for tax filing, Tax Identification Number (TIN)', 165::int),
    ('ACC 004', 4, '3', 'Tax Jurisdictions', 'Jurisdictions and Taxes Administered: Federal Administered Taxes; State Administered Taxes; Local Government Administered Taxes. Nigeria Tax Administration Act, 2025 – Section 3', 'Federal: Companies Income Tax, Taxation of Income from Petroleum, Capital Gains Tax, Value Added Tax, Development Levy, Withholding Tax and Personal Income Tax. State: Personal Income Tax, Capital Gains Tax (Individuals), Withholding Tax (Individuals), Market Fees, Motor Vehicles Licence and Land Use Charge. Local Government: Tenement Rate, Water Rate, Stall Fees, Radio Licence, Kiosks Fees, Market Fees, Naming of Roads.', 165::int),
    ('ACC 004', 5, '4', 'Basis Periods', 'Determination of Basis Periods for: New Trade; Change of Accounting Date; Cessation of Trade.', 'Commencement Rules, Change in Accounting Date Rules and Cessation Rules. Reference should be made to Finance Act 2023 where applicable.', 166::int),
    ('ACC 004', 6, '5', 'Introduction to Company Income Tax', 'Determination of Tax Liability. Introduction to Capital Allowance Nigeria Tax Act, 2025', 'Allowable and disallowable expenses, determination of assessable profits, chargeable profits and application of current corporate tax rate. Definition and types of capital allowance; balancing charge and balancing allowance excluding computation of capital allowance, balancing charge, balancing allowance and loss relief.', 166::int),
    ('BUS 001', 1, '1', 'Enterprise', 'The Nature of Business Activity and Objectives', 'Basic concepts of business. The scope of business. Types of business organizations. The character of business. The environment of business. (internal and external, characteristic of business environment); Significance of business enterprise; Why many businesses fail. The roles of government in business', 170::int),
    ('BUS 001', 2, NULL, NULL, 'The Role of the Entrepreneur', 'Concept of entrepreneur and entrepreneurship; traits of entrepreneurs and the roles of entrepreneurship in the development of a business and a country; types of entrepreneurs (e.g. serial, social, intrapreneur, scalable…etc )', 170::int),
    ('BUS 001', 3, NULL, NULL, 'The Social Enterprise', 'The aims of social enterprises; triple bottom line – Social, economic (financial), and environment.', 170::int),
    ('BUS 001', 4, '2', NULL, 'Economic Sector', 'Extractive, Manufacturing and Service sectors.', 170::int),
    ('BUS 001', 5, NULL, 'Business Structure', 'Legal Forms of Businesses', 'Forms of business: sole proprietorship, partnership, companies (unlimited, private limited and, public limited) franchise, co-operatives, public corporation and unincorporated companies; (features, advantages and disadvantages); problems resulting from changing from one legal structure to another. factors to be considered before choosing any form of business', 171::int),
    ('BUS 001', 6, '3', 'Size of Business', 'Measurement of Business Size', 'Types of Business Size (Small, Medium & Large Scale); Factors that are used to determine the size of a business.', 171::int),
    ('BUS 001', 7, NULL, NULL, 'Significance of Small Businesses', 'Concept of a small business; The importance of small businesses in the economy; Family Business (definition, Characteristics, importance, Reasons for family Business failure).', 171::int),
    ('BUS 001', 8, NULL, NULL, 'Forms of Business Growth', 'Business Growth Strategies {concentration (market penetration, market development & product development), integration (backward and forward integration), diversification (related & unrelated), cooperation (merger and acquisition)', 171::int),
    ('BUS 001', 9, NULL, NULL, 'National and Multi-National Businesses, Privatization/ Nationalization', 'National and multinational businesses (differences, merits and demerits); Privatization/ nationalization and internationalization. (merits/demerits)', 171::int),
    ('BUS 001', 10, '4', 'Stakeholders in a Business', 'Types and Responsibilities of Stakeholders', 'Definition and Types of stakeholders (Government, shareholders, customers, employees, host community and etc.) Responsibilities of stakeholders.', 171::int),
    ('BUS 001', 11, '5', 'Organisations', 'Organizational Structures', 'Meaning; Types of Organisations (formal & informal- meaning & examples) Definition & forms of organisational structure/departmentalization (Line and staff; functional, Divisional-product, customer, geographical/region, process) Matrix, Network, Remote or virtual); merits/demerits of each.', 172::int),
    ('BUS 001', 12, NULL, NULL, 'Dimensions of Organisational Structure Centralization and Decentralization', 'Specialization, Formalization Hierarchy & Span of Control Meaning: merits and demerits of centralization and decentralization', 172::int),
    ('BUS 001', 13, NULL, NULL, 'Delegation of Authority', 'Meaning of Delegation and reasons for delegating; why manager refuse to delegate; and subordinates’ resistance to delegation.', 172::int),
    ('BUS 001', 14, '6', 'Communication', 'Business Communication', 'Meaning of communication, types, process & channels of communication; Barriers to effective communication and solutions.', 172::int),
    ('BUS 002', 1, '1', 'Management and Leadership', 'Management Schools of Management Thoughts', 'Meaning; levels; functions (POSDCORB) and Managerial roles. Scientific, human relation, behaviour, bureaucratic, systems, management science and contingency. Universality and transferability of Management Management Problems in Nigeria Context', 173::int),
    ('BUS 002', 2, NULL, NULL, 'Leadership', 'Definition of Leadership Theories of Leadership (traits, great man & behavioural) Leadership styles (Autocratic, Democratic & Laissez faire) Leadership qualities (Integrity, Empathy, good initiative, Vision, Clear communication, Emotional Intelligence etc) Leadership grid (Blake-Mouton)', 173::int),
    ('BUS 002', 3, NULL, NULL, NULL, 'Principles and importance of corporate governance Leadership problems in organizations. Conflict in organizations and conflict management strategies.', 174::int),
    ('BUS 002', 4, '2', 'Motivation', 'Theories of Motivation', 'Meaning & types of motivation (intrinsic & extrinsic): Various Theorists of motivation (Maslow, Theory x & y, Herzberg, McClelland Needs theory, Vroom’s Expectancy theory and Equity theory, ERG, Goal- Setting)', 174::int),
    ('BUS 002', 5, '3', 'Human Resource Management (HRM)', 'Scope of HRM', 'Definition, and roles/functions of human resource management; recruitment and selection; job description, specifications; job enlargement, and employment contract; disciplinary procedures; staff morale and welfare, staff appraisal and Performance management, staff training and development, compensation and benefits.', 174::int),
    ('BUS 002', 6, '4', 'Marketing', 'Marketing', 'Meaning; role of marketing; marketing concepts; marketing mix and its elements; channels of distribution; market segmentation. Market share.', 174::int),
    ('BUS 003', 1, '1', 'Business Finance', 'Need for Business Finance', 'Nature of business finance; Scope, functions and risk of business finance. Types of capital (Start-up capital; capital for expansion; working capital)', 175::int),
    ('BUS 003', 2, NULL, NULL, 'Sources of Finance', 'Legal structure: sources and cost of finance (short term, medium term, long term); internal/external sources; factors influencing the sources of finance.', 175::int),
    ('BUS 003', 3, NULL, NULL, 'Financing', 'Introduction to financial decisions and financial markets. Risk and return. Capital investment decision. Capital expenditure and revenue expenditure', 175::int),
    ('BUS 003', 4, '2', 'Working Capital Management', 'Forecasting of Cash Flows', 'Cash flow forecasts in practice; methods of improving cash flow. Capital structure and options. Dividend policy.', 175::int),
    ('BUS 003', 5, NULL, NULL, 'Managing Working Capital', 'Meaning of working capital; calculation of working capital; importance of working capital; financing working capital (overdrafts, revolving credit facilities, invoice finance, etc). Time value of money. Net Present Value.', 175::int),
    ('BUS 003', 6, '3', 'Cost', 'Types of Costs', 'Fixed, variable, marginal, direct and indirect; uses of cost information.', 176::int),
    ('BUS 003', 7, NULL, NULL, 'Break Even Analysis', 'Definition & Calculation of Break-Even Analysis; Uses and limitations of break-even analysis', 176::int),
    ('BUS 003', 8, '4', 'Accounting Fundamentals', 'Source documents, subsidiary books and ledgers', 'Principle of Accounting: Business entity, Matching concept, Principle of double entry; Accrual, Prudency & Going – Concern etc. Definition and types of sources documents; (invoice, cheque books, vouchers, bank statements); Definition and types of ledgers;', 176::int),
    ('BUS 003', 9, NULL, NULL, 'Financial statement', 'Definition and preparation of income statement; Definition and preparation of financial position. Financial statements (balance sheet, profit & loss).', 176::int),
    ('BUS 003', 10, NULL, NULL, 'Ratio Analysis', 'Financial analysis:
Liquidity ratios; profitability ratios; shareholder ratios; gearing ratio; practical use of ratio analysis; limitations of ratios.', 176::int),
    ('BUS 003', 11, NULL, NULL, 'Depreciation', 'Meaning; role and calculation (Straight line & Reducing Balance)', 176::int),
    ('BUS 004', 1, '1', 'Operations Management Project Management', 'Nature of Operations', 'Definition of operations management; Inputs, outputs and the transformation process (using diagram to explain); effectiveness, efficiency and productivity; capital versus labour intensity. operating methods (job/ custom, flow/batch, mass/continuous; location and scale of operation (need for suitable location, factor influencing plant location)', 177::int),
    ('BUS 004', 2, NULL, NULL, 'Principles of Project Management', 'Concept and characteristics of project management The tools and techniques used in project management. Project life cycle. Projects bottle neck and possible solutions.', 177::int),
    ('BUS 004', 3, NULL, NULL, 'Inventory Management', 'Definition & Types of inventories (raw material, work in progress & finished goods, maintenance, repairs, operations; packaging and packaging materials, safety stock and anticipating stocks, cycle inventory, excess inventory etc: Purpose, costs and benefits of keeping inventory; ways of managing inventory.', 177::int),
    ('BUS 004', 4, '2', 'Strategic Management', 'Strategic Management', 'Overview of strategic management; Introduction to strategy and strategic management process; benefits of strategic management; Business vision/mission', 177::int),
    ('BUS 004', 5, NULL, NULL, NULL, 'statement and objectives; SWOT analysis; PESTLE analysis;', 178::int),
    ('BUS 004', 6, NULL, NULL, 'Strategy Formulation', 'Levels of Strategy- Corporate level Strategies (Growth, Stability, Retrenchment) Business Level strategies (Cost leadership, Differentiation & Focused or Niche) Functional Level strategies', 178::int),
    ('BUS 004', 7, NULL, NULL, 'Strategy Implementation', 'Meaning, importance and selection factors, procedural, resource allocation, structural & behavioral.', 178::int),
    ('BUS 004', 8, NULL, NULL, 'Strategy Evaluation & Control', 'Analysis and assessment and controlling strategic change.', 178::int),
    ('BUS 004', 9, '3', 'Green Management', 'The concept and principles of green management', 'Definition of green management. Principles of green management. Natural resource economics theory. Energy resources and eco-friendly technologies. (waste management, recycling and alternative energies) Green management applications in business functions. Climate change, global warming and sustainability.', 178::int),
    ('ECN 001', 1, '1', 'Introduction', 'a) Definition of Economics', 'Explain different historical and contemporary definitions of Economics.', 182::int),
    ('ECN 001', 2, NULL, NULL, 'b) Economics as a Social Science', 'Discuss what social sciences are and give examples of social activities and human behaviours.', 182::int),
    ('ECN 001', 3, NULL, NULL, 'c) Nature of Economic Problems', '• Identify and explain economic problems such as what, how and for whom to produce.
• Problems of scarcity of resources are to be linked with what, how and for whom to produce under different types of economic systems.', 182::int),
    ('ECN 001', 4, NULL, NULL, 'd) Scope and division of economics', '• Identify and explain economic agents (households, firms and the government).
• Identify and describe microeconomic concepts such as price system, welfare effects, efficiency determination, etc at the foundational level.
• Identify, describe and explain macroeconomic concepts such as national output, inflation, unemployment, international', 182::int),
    ('ECN 001', 5, NULL, NULL, NULL, 'trade, etc. at the foundational level.', 183::int),
    ('ECN 001', 6, '`2', 'Basic Economic Concepts and Production Possibility Curve', 'a) Scarcity, Choice and Opportunity Cost b) Production Possibility Curve c) Types of economic efficiency', '• Explain the basic concepts of scarcity, choice and opportunity cost using different examples.
• Explain the meaning of, shapes of and shifts in PPC.
• Explain different types of efficiency such as Pareto efficiency, productive efficiency and allocative efficiency. The types of efficiency should be taught with the aid of PPC.', 183::int),
    ('ECN 001', 7, '3', 'Classifications of economies and economic Systems', 'a) Historical classifications of economies b) Classifications of economic systems', 'Explain historical classifications of economies:
o Advanced and backward economies o First-world and third world economies o Developed and underdeveloped economies o Developed and developing economies o Large and small economies Explain ideologies, features and structure of economic systems:
o Market economy o Planned economy o Mixed economy', 183::int),
    ('ECN 001', 8, '4', 'Taxonomy of goods', 'Classification of goods', 'Explain different classifications (definitional) of goods:', 183::int),
    ('ECN 001', 9, NULL, NULL, NULL, 'o Economic and non-economic goods o Public and private goods o Consumer and capital goods o Normal and inferior goods o Merit and demerit goods', 184::int),
    ('ECN 001', 10, '5', 'Tools, Methods and Methodology of Economic Analysis', 'a) Inductive and deductive methods b) Positive and normative statements c) Functional relationships such as: dependent and independent variables d) Interpretation and comprehension of statistical data presented in form of charts, tables and graphs e) Application and the use of statistical data.', '• Explain inductive and deductive methods with examples
• Explain positive and normative statements with examples
• Introduce types of economic data (time series, cross sectional and panel data) to students. Only basic knowledge should be taught
• Acquaint students with the knowledge of interpreting economic data presented in form of charts, tables and graphs as well as using mathematical equations to explain relationships among economic variables', 184::int),
    ('ECN 001', 11, '6', 'Theory of Consumer Behaviour', 'a) Concept of utility b) Law of diminishing marginal utility c) Equi-marginal principle/utility-maximizing rule d) Derivation of demand curve from marginal utility analysis e) Limitations of marginal utility theory', '• Discuss the determination of demand curve from the law of diminishing marginal utility
• Explain the limitations of marginal utility
• Explain the meaning, shape and properties of indifference curve
• Explain the MRS with illustrations', 184::int),
    ('ECN 001', 12, NULL, NULL, 'f) Indifference curve g) Marginal rate of substitution h) Budget lines i) Income and substitution effects of a price change', '• Explain the meaning, types and properties of budget lines
• Explain rotation and shift in budget lines
• Illustrate and explain income and substitution effects of price change for normal goods
• Explain the determination of consumer equilibrium under the ordinal approach
• Explain the derivation of price consumption curve (PCC) and income consumption curve (ICC)', 185::int),
    ('ECN 001', 13, '7', 'The price theory', 'a) Individual and market demand b) Factors determining demand c) Change in quantity demanded and change in demand d) Elasticity of demand (price, income and cross) e) Individual and market supply f) Factors determining supply g) Movement along and shift in supply curve h) Elasticity of supply (price) i) Interaction of demand and supply j) Government intervention in the market', '• Explain individual and market demand functions and curves
• Explain factors affecting individual and market demand o Price of the commodity o Prices of other commodities (substitutes and complements) o Consumer’s income o Tastes and fashion o Population
• Distinguish between change in quantity demanded and change in demand
• Explain the concepts of elasticity, elasticity of demand and types of elasticity of demand
• Discuss and interpret formulas to calculate elasticity of demand o Percentage formula o Point formula o Arc formula
• Explain factors affecting individual and market supply o Price of the commodity o Prices of other commodities (substitutes and complements) o Production cost o Government policy o Number of firms
• Distinguish between change in quantity supplied and change in supply
• Explain the concept and types of elasticity of supply', 186::int),
    ('ECN 001', 14, NULL, NULL, NULL, '• Discuss and interpret formulas to calculate elasticity of supply o Percentage formula o Point formula o Arc formula
• Explain the concept of market equilibrium and market disequilibrium
• Explain changes in market equilibrium caused by:
o Change in demand while supply is constant o Change in supply while demand is constant o Simultaneous change in demand and supply
• Demonstrate calculations on determination of equilibrium price, equilibrium quantity, excess demand and excess supply', 187::int),
    ('ECN 001', 15, '8', 'Theory of the firm and market structure.', 'a) Meaning of firm and industry b) Definition of production c) Factors of production (land, labour, capital, entrepreneur and technology) d) Production function. e) Short-run production f) Long-run production g) Production costs h) Law of variable proportions i) Theory of costs', '• Explain the meaning of firm and industry, production, factors of production (variable and fixed factors) and their rewards, mathematical representation of production function
• Explain the total product, average product, marginal product and their graphical representations
• Explain the law of diminishing returns (law of', 187::int),
    ('ECN 001', 16, NULL, NULL, 'j) Economies and diseconomies of scale k) Revenue l) Profits m) Elasticity and revenue', 'variable proportion) and its application especially in agric industry
• Explain and discuss the shapes of long run and short run average cost curves.
• Explain the various cost concepts o Fixed costs and variable costs o Average fixed costs and average variable costs o Total costs and marginal costs o Implicit costs and explicit costs o Accountant’s and economist’s views of costs
• Discuss isoquants and isocosts
• Explain the concepts and sources of economies and diseconomies of scale
• Explain the concepts of revenue (total, average and marginal)
• Explain different forms of profits (economic, accountant and normal)
• Discuss the relationship between price elasticity of demand and total revenue of the seller', 188::int),
    ('ECN 001', 17, '9', 'Market Structure', 'a) Types of market structures: b) Types of imperfect markets c) Profit maximization', '• Explain the types of market structure (perfect and imperfect)', 188::int),
    ('ECN 001', 18, NULL, NULL, 'd) Price discrimination', '• Explain the types of imperfect market structure (monopolistic competition, monopoly and oligopoly)
• Explain the characteristics of different management structures
• Explain profit-maximizing behaviours of different market structures in the short run and long run
• Explain and distinguish between the concepts of price discrimination and product differentiation', 189::int),
    ('ECN 002', 1, '1', 'Circular flow of income', 'a) Circular flow of income b) Leakages and injections', '• Explain circular flow of income
• Describe the circular flow of income in 2-sector, 3-sector and 4-sector economies
• Describe circular flow with financial sector in the chart
• Explain the components of aggregate leakages and aggregate injections', 190::int),
    ('ECN 002', 2, '2', 'National income accounting', 'a) Basic concepts of national income accounting b) Methods of measuring national income c) Problems arising from national income measurement d) Determinants and uses of national income statistics', '• Explain and give examples of basic concepts of GDP, GNP, NDP, NNP, personal income and personal disposable income
• Explain approaches to measuring GDP o Income approach o Output approach o Expenditure approach
• Explain with examples GDP at basic prices (factor cost) and market prices
• Discuss the problems arising from computing the GDP (limitations of GDP)
• Explain determinants of national income and their uses', 190::int),
    ('ECN 002', 3, '4', 'Money and Banking', 'a) Nature and evolution of money b) Properties and functions of money c) Demand for money d) Supply of money e) Quantity theory of money f) Classical theory of interest rate determination', '• Discuss the nature and evolution of money
• Explain the properties and functions of money
• Explain the meaning and motives of demand for money
• Explain the supply of money
• Explain the quantity theory of money (MV = PY)', 190::int),
    ('ECN 002', 4, NULL, NULL, 'g) Financial institutions', '• Explain the classical theory of interest rate determination
• Forces of money demand and money supply
• Explain the functions of financial institutions with reference to the Nigerian economy:
o Central bank o Commercial banks o Merchant banks o Development banks o Mortgage banks o Non-bank financial institutions (insurance companies, pension funds, etc)', 191::int),
    ('ECN 002', 5, '5', 'Public Finance', 'a) Concept and subject matter of public finance b) Sources of Government Revenue c) Principles and types of taxation d) Problems of tax revenue e) Concept and classifications of government expenditure f) Budgets g) Public Debt h) Reasons for public debt i) Debt management', '• Explain the definition of public finance.
• Explain the subject matter of public finance
• Explain the tax and non-tax sources of revenue of the government
• Explain the canons of taxation
• Explain and illustrate direct and indirect taxes
• Explain the problems associated with tax revenue collection o Tax evasion o Tax avoidance
• Explain the meaning and components of government expenditure
• Explain the classifications (capital and recurrent) of government expenditure', 191::int),
    ('ECN 002', 6, NULL, NULL, NULL, '• Explain the meaning and types of budgets o Deficit budget o Surplus budget o Balanced budget
• Explain the meaning and forms of public debt o Domestic debt o External debt
• Explain reasons for debt accumulation', 192::int),
    ('ECN 003', 1, '1', 'Economic Growth and Development', 'a) Economic growth b) Concept of economic development c) Indicators of economic development d) Characteristics of developed and Less-Developed Countries (LDCs) e) Comparison of economic growth and economic development f) Business cycle', '• Explain the meaning and sources of economic growth
• Explain the indicator and calculation of GDP growth rate
• Explain the meaning of economic development
• Explain the indicators of economic development o Human development index o Multidimensional poverty index
• Discuss the main characteristics of LDCs o Low GNI per capital o High level of poverty o Low-quality human capital o Deficient infrastructure o Weak institutions o Low-quality social-economic amenities/services
• Distinguish between economic growth and economic development
• Discuss business cycle with particular reference to the Nigerian economy', 193::int),
    ('ECN 003', 2, '2', 'Economic Structure of Nigeria', 'a) Agricultural sector b) Industry sector c) Service sector', 'Explain the structure and contribution of sectors to the Nigerian economy:
Agric sector (crop production, livestock, fishery and forestry)', 193::int),
    ('ECN 003', 3, NULL, NULL, NULL, 'Industry sector (oil, construction, manufacturing, mining, etc) Services (telecommunication, banking, trade, etc)', 194::int),
    ('ECN 003', 4, '3', 'Economic structure of West Africa', 'a) Agricultural sector b) Industry sector c) Service sector d) Sub-regional comparison', 'Explain the structure and contributions of the sectors to the economy of West Africa Compare the structure of West African economy with that of other sub-regions such as East Africa, Southern Africa, North Africa, East Asia, Southern Asia and Latin America', 194::int),
    ('ECN 003', 5, '4', 'Population', 'a) History of world population growth b) Structure and geographical distribution of world population c) Population structure and the labour force d) Malthusian population theory e) Demographic transition f) Other terms in population studies (population cycle, optimum population, underpopulation, overpopulation, population explosion, population explosion, etc g) Socio-economic impact of population dynamics h) Trends in population dynamics', '• Explain the historical development of population across the world
• Explain the structure and geographical distribution of world population across different continents and regions
• Explain the relationship between population structure and labour force
• Explain the Malthusian population theory and its implications/limitations in contemporary societies
• Discuss other terms in population studies
• Explain the socio-economic impact of poverty, income, healthcare, etc on population
• Explain trending issues on population: HIV/AIDS, LGBTQ+, etc', 194::int),
    ('ECN 003', 6, '5', 'International trade', 'a) Definition of international trade b) Benefits and problems of international trade. c) Theories of international trade d) Determinants of trade flows. e) Arguments for Free Trade and restricted trade f) Types of trade protection and their effects g) Terms of Trade', '• Explain the meaning of international trade
• Explain the benefits and problems of international trade
• Explain and illustrate Smithian and Ricardian theories of international trade
• Explain the determination of trade flows from Smithian and Ricardian theories
• Explain the arguments and against free trade and restricted trade
• Explain tariff and non-tariff barriers to international trade and their effects on trade flows
• Explain the terms of trade and their implications', 195::int),
    ('ECN 003', 7, '6', '. B alance of payments and exchange rate', 'a) Meaning of balance of payments (BOP) b) Components of BOP c) Balance of payments equilibrium and disequilibrium d) Meaning of exchange rate e) Fluctuations in exchange rates f) Types of exchange rates g) Determination of exchange rates h) Effects of exchange rate fluctuations on BOP', '• Explain the meaning of BOP
• Explain the components of BOP:
o Current account o Capital and financial account o Net errors and omissions
• Explain the meaning and implications of BOP equilibrium and disequilibrium
• Explain the meaning of exchange rate
• Explain the factors underlying fluctuations in exchange rate
• Explain types of exchange rate o Nominal exchange rate o Real exchange rate o Weighted exchange rate', 195::int),
    ('ECN 003', 8, NULL, NULL, NULL, '• Explain the determination of exchange rate (exchange rate regimes) o Fixed exchange rate regime o Floating exchange rate regime o Managed-float exchange rate regime
• Discuss the effects of exchange rate fluctuations on BOP', 196::int),
    ('ECN 004', 1, '1', 'Government Intervention', 'a) Forms of government intervention b) Sources of Market Failure b) Objectives of Government intervention c) Policies to Correct Market Failure:', '• Explain the forms of government intervention o Indirect taxes and subsidies o Maximum price and minimum price controls o Direct intervention
• Explain sources of market failure o Externalities o Public goods o Merit and demerit goods o Imperfect competition', 196::int),
    ('ECN 004', 2, NULL, NULL, NULL, 'o Asymmetric information
• Explain objectives of government intervention o Efficiency o Equity o Income distribution
• Explain policies to correct market failure o Regulation o Wealth redistribution o Privatization Taxes and subsidies', 197::int),
    ('ECN 004', 3, '2', 'Inflation and unemployment', 'a) Concept of inflation b) Theories of inflation c) Measure of inflation rate d) Types, causes, effects and remedies of inflation e) Concept of unemployment f) Measure of unemployment rate g) Types, causes, effects and remedies to curb unemployment in Nigeria. h) Stagflation i) Phillips curve', '• Explain the meaning of inflation
• Explain the theories of inflation o Keynesian theory o Monetarist theory
• Explain the computation of inflation rate from CPI
• Explain the types of inflation o Demand-pull inflation o Cost-push inflation o Hyperinflation o Creeping inflation
• Explain the causes, effects and remedies of inflation
• Explain the meaning of unemployment
• Explain the computation of unemployment rate
• Explain the types of unemployment o Cyclical unemployment o Frictional unemployment', 197::int),
    ('ECN 004', 4, NULL, NULL, NULL, 'o Structural unemployment o Seasonal unemployment
• Explain the causes, effects and remedies of unemployment
• Explain the meaning and implication of stagflation
• Explain the meaning and implication of Phillips curve o Short-run Phillips curve o Long-run Phillips curve', 198::int),
    ('ECN 004', 5, '3', 'Applied issues in macroeconomics', 'a) Inflationary and deflationary gaps b) Schools of economic thought c) Deficit financing and economic growth d) Fuel subsidy removal', '• Explain the determination of inflationary and deflationary (recessionary) gaps using the withdrawal-injection approach
• Discuss the main schools of economic thought
• Explain the meaning and sources of deficit financing
• Explain the implications of deficit financing on macroeconomic growth
• Discuss the implications of fuel subsidy removal on the Nigerian economy', 198::int),
    ('ECN 004', 6, '4', 'Applied Issues in Labour Economics', 'a) Demand for labour b) Supply of labour c) Wage determination d) Role of trade union on wage determination e) Wage differential', '• Explain the meaning of demand of labour
• Explain the factors affecting demand for labour
• Explain the marginal productivity theory of demand for labour', 198::int),
    ('ECN 004', 7, NULL, NULL, NULL, '• Explain the supply of labour:
o Individual supply of labour o Industry supply of labour
• Explain the determination of wage using the market forces of demand for and supply of labour o Labour market equilibrium o Labour market disequilibrium
• Explain the role of trade union and government in wage determination', 199::int),
    ('ECN 004', 8, '5', 'Macroeconomic Policies in Developing Countries', 'a) Objectives of macroeconomic policies b) Types of macroeconomic policies c) Conflicts between policy objectives', '• Explain the stabilization objectives of macro policy (price stability, full employment, BOP equilibrium, income equality)
• Explain the growth objective of macro policy (economic growth)
• Explain the types and instruments of macro policies:
o Fiscal policy o Monetary policy o Exchange rate policy o Supply-side policy o Trade policy
• Discuss the conflicts that may occur in a pair macro goals', 199::int),
    ('ECN 004', 9, '6', 'Globalization and international economic institutions', 'a) Meaning of economic integration b) Types and benefits of economic integration c) Foreign investment d) Globalization e) International organizations', '• Explain the meaning of economic integration
• Explain the types (or stages) of economic integration and their benefits
• Explain and distinguish between foreign direct investment and foreign portfolio investment
• Explain the meaning and implication of globalization in contemporary world
• Explain the functions of international organizations:
o Trade blocks:
ECOWAS, EU, WTO, BRICS o International financial institutions: World Bank, AfDB, IMF o Cartel: OPEC', 200::int),
    ('GRY 001', 1, '1', 'Introduction to Physical Geography', 'Meaning and Scope', '• Definition of Geography;
• Meaning and scope of Physical Geography;
• Relevance of Physical Geography to human activities and environmental studies', 204::int),
    ('GRY 001', 2, NULL, NULL, 'Branches of Physical Geography', 'Geomorphology, climatology, hydrology, biogeography, soil geography', 204::int),
    ('GRY 001', 3, '2', 'Introduction to Earth System', 'Earth System & Processes', '• The Basic Characteristics of the Earth (The Shape and Size of the Earth);
• Proof of its Sphericity;
• The Earth’s Movement – Rotation (Day & Night), Revolution (Seasons);
• The Spheres of the Earth (Atmosphere, Biosphere, Lithosphere and Hydrosphere);', 205::int),
    ('GRY 001', 4, '3', 'The Structure of the Earth', 'The internal structure of the Earth', '• Description of the internal structure of the Earth;
• Rocks and Minerals;
• Classification of rocks (Igneous, Sedimentary and Metamorphic);
• Mode of Formation of each type of rock;
• The basic characteristics of each type of rock.', 205::int),
    ('GRY 001', 5, NULL, NULL, 'Tectonic Movements and Landforms', '• Introduction to Tectonic Movement;
• Types of Plate Boundaries;
• Landforms associated with Plate Movement (Mountain, Plateau, Valleys and Plain);
• Areas where each landform type is predominant;
• Importance of the major landform on the Earth’s surface.', 205::int),
    ('GRY 001', 6, '4', 'Weather & Climate', 'Earth’s Atmosphere', '• The composition of the Atmosphere;
• The structure (different layers) of the Atmosphere;
• Description of the characteristics of each of the layers.', 205::int),
    ('GRY 001', 7, NULL, NULL, 'Elements of Weather & Climate', '• Identification of the various elements or components of Weather (Temperature, Precipitation, Wind Humidity, Pressure, Insolation (Solar radiation);', 206::int),
    ('GRY 001', 8, NULL, NULL, 'Climatic Factors', '• Climatic Factors: Energy and Water balance (Hydrological Cycle);
• Factors affecting Weather & Climate;
• Geographical Coordinates and location of Climatic Zones on Earth.', 206::int),
    ('GRY 001', 9, '5', 'Denudation', 'Weathering Processes', '• Definition of Denudation and its agents;
• Description of Weathering & Erosion;
• Difference between Weathering & Erosion;
• Definition & Processes of Weathering;
• Types of Weathering (Physical, Chemical & Biological);
• Factors affecting Weathering.', 206::int),
    ('GRY 001', 10, NULL, NULL, 'Mass Movement', '• Description of Mass Movement;
• Processes of Mass Movement;
• Types of Mass Movement;
• Landforms resulting from Mass Movement.', 206::int),
    ('GRY 001', 11, '6', 'Introduction to Hydrology', 'Hydrology and Drainage Basin System', '• Introduction to the science of hydrology. The hydrological cycle. The Drainage Basin as a System (Inputs, Outputs, Stores and Flows);
• Description of the Drainage Basin Hydrological Cycle;', 206::int),
    ('GRY 001', 12, NULL, NULL, NULL, '• Differences between Overland Flow, Through flow and Base flow;
• Factors that influence Infiltration.', 207::int),
    ('GRY 001', 13, '7', 'Landform Processes', 'Fluvial Processes & Landforms', '• Description of Landforms Associated with Running Water (River channel processes and landforms);
• Landforms associated with each stage of a river;
• Coastal Environment (Coastal Processes and Landforms; Wave Action);
• Description of Landforms resulting from coastal and deposition.', 207::int),
    ('GRY 001', 14, NULL, NULL, 'Aeolian Processes & Landforms', '• Description of different types of desert landscapes;
• Description of Aeolian Processes (wind erosion, transport and deposition);
• Description of Arid, Granite and Karst environments;', 207::int),
    ('GRY 001', 15, NULL, NULL, 'Glacial Processes & Landforms', '• Understanding the glacial environment;
• Explanation of glacial processes (erosion, transportation and deposition);
• Landforms resulting from glacial processes.', 207::int),
    ('GRY 001', 16, '8', 'Soil and Vegetation', 'Soil', '• Definition of soil;
• Factors and processes of Soil formation;
• Basic soil types, composition and characteristics;
• Description of soil profile.', 207::int),
    ('GRY 001', 17, NULL, NULL, 'Vegetation', '• Meaning of Vegetation;', 207::int),
    ('GRY 001', 18, NULL, NULL, NULL, '• Vegetation types and underlying factors;
• Ecological interrelationship between Soil and Vegetation;', 208::int),
    ('GRY 001', 19, '9', 'Introduction to Environmental Sciences', 'Understanding Environmental Sciences', '• Definition of environmental science;
• Multidisciplinary nature of environmental science;
• Components of the environment;
• Environmental concepts,
• Environment as a system;
• Energy systems in the atmosphere, biosphere, hydrosphere, and lithosphere.', 208::int),
    ('GRY 001', 20, '10', 'Environmental Hazards & Management', 'Environmental Hazards', '• Definition of Environmental Hazards;
• Types of Environmental Hazards;
- Climatic Hazard (Climate change, Tsunamis, Hurricanes, Tornadoes, Floods; Drought, Soil erosion, etc.);
- Biological (infestation, Covid-19, Faunal disease;
- Geological Hazard (Earthquake, Land slide, Volcanism, etc.);
- Anthropogenic Hazard (Air pollution, Wildfire, Deforestation, etc.). Causes of Environmental Hazards.', 208::int),
    ('GRY 001', 21, NULL, NULL, 'Management of Environmental Hazards', '• Different ways of sustainable management of Environmental Hazard (Response, Recovery, Mitigation)', 208::int),
    ('GRY 002', 1, '1', 'Introduction to Human Geography', 'Concerns for Human Geography', '• Definition and scope of Human Geography.
• Relationship between Human and Physical Geography;
• Themes & Key concepts in Human Geography (Location, Movement, Interaction, Region, Place, Space)
• Importance of Human Geography.
• Branches of Human Geography (Population, Economic, Transportation, Cultural, Political, urban, Social geography, etc)', 209::int),
    ('GRY 002', 2, '2', 'The Cultural Environment', 'The Human or Cultural Landscape', '• Meaning of culture
• Types of Culture (Material and Non-Material Culture);
• Components of culture (cultural trait, cultural complex, cultural system, and cultural region)
• Basic cultural terms and components (cultural convergence, divergence, acculturation, assimilation, trans-culturation, ethnicity, pop culture, folk culture, cultural imperialism, cultural nationalism)
• Language and Religion as basic components of culture;
• Explanation of difference between Human or Cultural landscape and Natural Landscape.', 210::int),
    ('GRY 002', 3, NULL, NULL, 'Cultural Diffusion', '• Definition of Cultural Diffusion
• Types of Cultural Diffusion e.g. Expansion e.g. (Hierarchical, stimulus, and Contagious) and Relocation.
• Factors that promote or retard Cultural Diffusion;
• The role of communication systems and technology in cultural innovation and idea diffusion', 210::int),
    ('GRY 002', 4, '3', 'Man-Environment Interaction', 'Concepts of Man-Environment Relationship', '• Interdependence of human and physical environmental systems.
• Man-Environment Interaction
• Definition of Cultural Ecology;', 210::int),
    ('GRY 002', 5, NULL, NULL, NULL, '• Concepts of Environmental Determinism, Probabilism and Possibilism.
• The role of physical factors on human activities (e.g., influence of relief, climate, vegetation, soils, and water on settlement and economic life) and vice versa', 211::int),
    ('GRY 002', 6, '4', 'Population Geography', 'Population Distribution', '• Meaning of Population and Demography;
• Population concepts (Over population, under population, Optimum population, Population density, Population distribution);
• Patterns of Population distribution
• Factors influencing Population Distribution (physical, economic, social, political, historical', 211::int),
    ('GRY 002', 7, NULL, NULL, 'Population Growth', '• Components of Population growth or Change (Birth rate, Death rate and Migration);
• Patterns and trends of Population Growth
• Demographic Transition Model', 211::int),
    ('GRY 002', 8, NULL, NULL, 'Population Structure', '• Population Composition (Sex Ratio, Age Structure, Population Pyramid, Dependency Ration, Rural-Urban Composition, Literacy level, Occupational Structure);', 211::int),
    ('GRY 002', 9, NULL, NULL, 'Migration', '• Meaning
• Forms of Migration (Internal and international migration)', 211::int),
    ('GRY 002', 10, NULL, NULL, NULL, '• The Push and pull factors responsible for the volume and pattern of Migration
• Effects and Solution of Migration (Social, economic and environmental effects)', 212::int),
    ('GRY 002', 11, NULL, NULL, 'Population Census', '• Meaning
• Types (De-facto, De-jure, Census by assembly)
• Importance and Problems of Population Census', 212::int),
    ('GRY 002', 12, '5', 'Settlement Geography', 'Origin of Settlements', '• Meaning of Human Settlement;
• Origin and stages of human settlement development (nomadic → agrarian → urban);
• Factors influencing the location of settlement;
• Factors affecting the growth of settlement', 212::int),
    ('GRY 002', 13, NULL, NULL, 'Settlement Patterns', 'Patterns and forms of human settlement distribution (nucleated or dense, isolated, dispersed or scattered, linear, planned, etc.)', 212::int),
    ('GRY 002', 14, NULL, NULL, 'Types of Settlements', '• Rural and urban settlements;
• Major problems of rural and urban settlement;
• Interdependence between rural and urban settlement (Flows of goods, services, information, and people), Urban influence zones (hinterlands)
• Problems associated with rural–urban relationships (e.g. Rural–urban migration and depopulation, Urban bias and rural neglect, etc.);', 212::int),
    ('GRY 002', 15, NULL, NULL, NULL, '• Strategies for balancing urban and rural development (e.g. integrated rural development; Decentralization and regional planning, etc.).', 213::int),
    ('GRY 002', 16, NULL, NULL, 'Classification of settlement', '• By Form and hierarchy (homestead, farmstead, hamlet, village, town, city, metropolis, conurbation, megalopolis);
• By Population size;
• By Function (residential, trade, industrial, mining, defence, administrative, etc.),
• Site and situation,
• Cultural characteristics;', 213::int),
    ('GRY 002', 17, '6', 'Urbanization', 'Urbanization', '• Meaning of Urbanization;
• Factors of Urbanization;
• Impacts of Urbanization.', 213::int),
    ('GRY 002', 18, '7', 'Agricultural Land Use', 'Agricultural Systems', '• Meaning of Agriculture;
• Factors that affect Crop distribution pattern;
• Types of Agricultural Farming System (Subsistence & Commercial farming) with examples (Nomadic Herding, shifting Cultivation, Paddy rice, Plantation, Market Gardening, Livestock farming, Dairying, Ranching, Grain Farming);
• Introduction to livestock agriculture (Cattle rearing, Poultry, Piggery);
• Economic Benefits of Agriculture; Challenges of Agriculture.', 213::int),
    ('GRY 002', 19, '8', 'Human Transportation', 'Transportation Systems, Benefits & Challenges', '• Definition of Transportation;
• Types of Transportation systems e.g. land (rail and road), water (inland and ocean), air, and pipeline;
• world major ocean routes
• Movement of Goods and People (Trade routes, transport networks and spatial interaction)
• Contributions of transportation to economic development; Transportation challenges and their solutions.', 214::int),
    ('GRY 002', 20, '9', 'Industrialization', 'Industrial Development', '• Definition of Industrialization;
• Factors of Industrial location;
• Types / classifications of industries;
• Impacts of Industrialization; Challenges of Industrialization.', 214::int),
    ('GRY 002', 21, '10', 'Tourism', 'Introduction to Tourism', '• Meaning and Importance of Tourism;
• Types of Tourism. •', 214::int),
    ('GRY 002', 22, NULL, NULL, 'Element of Geo-Tourism', '• Meaning of Geo-tourism;
• Examples of Geo-tourism;
• Characteristics & Factors of Geo-tourism;
• Benefits of Geo-tourism (economic, social, environmental); Negative impact of Geo-tourism.', 214::int),
    ('GRY 002', 23, '11', 'Political Geography', 'State and Nation', '• Meaning, Scales and Scope of political Geography;
• Independent and Dependent Countries of the world;', 214::int),
    ('GRY 002', 24, NULL, NULL, NULL, '• Meaning and characteristics of states and nations;
• Territorial Morphology -shapes and size of a State (e.g. Compact, prorupted, elongated, fragmented, perforated) with their advantages and disadvantages;', 215::int),
    ('GRY 002', 25, NULL, NULL, 'Political Boundaries', '• Types (Geometric, Physical, cultural, complex, Relic, Antecedent, Subsequent, Superimposed);
• Functions of boundaries.', 215::int),
    ('GRY 002', 26, '12', 'Field Work', 'Study of human features of the local environment, and the relationship between the human and physical environments. This will involve data collection, analysis and reporting', NULL, 215::int),
    ('GRY 003', 1, '1', 'Introduction to Maps', 'Meaning and Characteristics of Map', '• Definition of Map;
• Characteristics of Map;
• Components or elements of Map;
• Types of Map;
• Uses of Map.', 216::int),
    ('GRY 003', 2, '2', 'Geographical Coordinates & Measurements', 'Location & Direction', '• Direction (Bearing and Cardinal Points);
• Grid References;
• Latitudes and Longitudes;
• Scales (Statement Scale, Representative Fraction, Linear Scales);
• Scale Conversion;
• Uses of Scales.', 216::int),
    ('GRY 003', 3, NULL, NULL, 'Measurements', '• Measurement of Distance;
• Road Network Connectivity;
• Calculation of Area;
• Enlargement and Reduction of Maps.', 216::int),
    ('GRY 003', 4, '3', 'Maps Symbols', 'Conventional Signs for representing physical (Natural) Features', '• Key conventional signs for Physical Features (Rocks, Outcrops, Cliffs, Sand Dunes, Crater, Quarry and Waterhole, Well, Spring, Streams/Water bodies e.g. Waterfall, Rapids, Lake, Pond, Dam, Bridge, Sand, etc.);
• Vegetation (Forest, Savannah, Orchard bush, Park, Scrub, Swamp/Marsh); Boundaries;', 216::int),
    ('GRY 003', 5, NULL, NULL, 'Conventional Signs for Representing Cultural (Man-Made) Features', '• Settlement (Built-up areas, Isolated Compounds, Towns, Town Walls, Villages, Cities);
• Communication (Roads, paths, Railways, Airport).', 217::int),
    ('GRY 003', 6, NULL, NULL, 'Conventional Signs for Representing Relief (Landform) Features', '• Recognition of Landforms (Spot height, Trigonometric Stations, Benchmarks, Contours, Form Lines);
• Layer Colouring.', 217::int),
    ('GRY 003', 7, '4', 'Relief Analysis', 'Descriptive Relief Analysis', '• Recognition of the Contour lines and shape outline of different types of Landforms;
• Landforms and their Contour Representation e.g. Valley, Spur, Ridge, Plateau, Escarpment, Col /Saddles, Gap, Pass, Scarps, Plateau Massif, Plains, Dissected Highlands,
• Slope Types (even, gentle, steep, concave, convex, straight and composite).', 217::int),
    ('GRY 003', 8, NULL, NULL, 'Quantitative Relief Analysis', '• Calculation of Gradient;
• Relief Profiles (Cross Profiles or Profiles along routes).', 217::int),
    ('GRY 003', 9, '5', 'Morphometric Analysis', 'Drainage Analysis', '• Definition of Drainage Analysis;
• Types of Drainage Pattern;
• Stream Ordering;
• Bifurcation Ratio;
• Drainage Density
• Stream Frequency;
• Length Ratio;
• Drainage Intensity.', 217::int),
    ('GRY 003', 10, '6', 'Analysis of Cultural Features', 'Interpretation of Cultural Phenomena', '• Various settlement types and Spatial distribution;
• Communication patterns (Communication lines,', 217::int),
    ('GRY 003', 11, NULL, NULL, 'on Topographic Maps', 'telecommunication cables, powerlines, pipelines, roads, railways, flight paths, etc.);
• Socio-economic activities (agriculture, tourism, mining, etc).', 218::int),
    ('GRY 003', 12, '7', 'Analysis of Spatial Relationships', 'Inter-relationships between Cultural and Physical Features on Topographic Maps', '• Analyzing the interrelationship between Settlement and Physical Features;
• Transport route and Physical Features;
• Agriculture and Physical Features; Mining and Physical Features.', 218::int),
    ('GRY 003', 13, '8', 'Graphical Presentation of Geographical Data', 'Statistical Graphs', '• Statistical Graphs defined;
• Importance of Statistical Graphs (Why Geographers use Statistical Maps);
• Types of Statistical Maps
- Divided circles (Pie charts);
- Line graphs (Simple, Group, Compound, Divergence, Cumulative);
- Histogram
- Bar Graphs (Simple, Group, Compound);
- Age and Sex pyramid.', 218::int),
    ('GRY 003', 14, NULL, NULL, 'Statistical Maps', '• Statistical maps defined.
• Types of Statistical Maps:
- Dot maps
- Isopleth (Isoline, Isarithmic) maps;
- Choropleth maps;
- Flowline maps', 218::int),
    ('GRY 003', 15, '9', 'Introduction to Geographic Information', 'Geographic Information System (GIS) and its Applications', '• Meaning of GIS;
• Components or Elements of GIS;
• Applications of GIS.', 218::int),
    ('GRY 003', 16, NULL, 'Systems and Remote Sensing', 'Remote Sensing', '• Definition of Remote Sensing
• Elements of Remote Sensing
• Advantages and disadvantages of Remote Sensing
• Remote sensing Applications
• Uses of Remote Sensing in map making', 219::int),
    ('GRY 003', 17, '10', 'Field and Laboratory Works in Practical Geography', 'Students are to Demonstrate skills in data collection and analysis on the field and in the laboratory using Cartographic /GIS equipment.', NULL, 219::int),
    ('GRY 004', 1, '1', 'Introduction to Regional Geography', 'Understanding Regional Geography', '• Meaning of Regional Geography.
• Concept of Regions.
• Scope of GRY 004 (the regions covered in the', 219::int),
    ('GRY 004', 2, NULL, NULL, NULL, 'course include: Nigeria, West Africa, Africa & North America)', 220::int),
    ('GRY 004', 3, '2', 'Location of the Regions', 'Location', 'Location, Size, Geopolitical Divisions of Nigeria, West Africa, Africa, and North America.', 220::int),
    ('GRY 004', 4, '3', 'Physical Environment of the Regions', 'Climate', 'Climatic characteristics of Nigeria, West Africa, Africa and North America', 220::int),
    ('GRY 004', 5, NULL, NULL, 'Relief and Drainage', 'Major landforms and river systems in the regions', 220::int),
    ('GRY 004', 6, NULL, NULL, 'Vegetation and Soils', 'Vegetation belts and soil types of Nigeria, West Africa, Africa, and North America', 220::int),
    ('GRY 004', 7, '4', 'Human Environment of the Regions', 'Population', 'Population distribution, and density of Nigeria, West Africa, Africa, and North America', 220::int),
    ('GRY 004', 8, NULL, NULL, 'Settlements', 'settlement patterns: Rural and urban settlements and functions within the regions', 220::int),
    ('GRY 004', 9, NULL, NULL, 'Culture', 'Definition, types and different major Ethnicity, Language and Religion of Nigeria, West Africa, Africa, and North America.', 220::int),
    ('GRY 004', 10, '5', 'Spatial Organization', 'The Concept of Spatial Organization', 'Meaning, Types and Importance of Spatial Organization', 220::int),
    ('GRY 004', 11, '6', 'Geographical Region', 'Region and its types', '• Meaning of Region;
• Types of Region (Homogenous, Functional & Perceptual Regions);
• Definition of Regional Development;
• Regional Disparities in Social and Economic Development within Countries);
• Causes and consequences of regional disparity within countries.', 221::int),
    ('GRY 004', 12, '7', 'Regional Economy', 'Economic Development', '• Economic activities in Nigeria, West Africa, Africa, and North America.', 221::int),
    ('GRY 004', 13, NULL, NULL, 'Agriculture', '• Agricultural activities and regions within Nigeria, West Africa, Africa, and North America.
• Importance and problems of agriculture in the different regions;', 221::int),
    ('GRY 004', 14, NULL, NULL, 'Mining', '• Mineral resources and mining activities in Nigeria, West Africa, Africa and North America;
• Importance and problems of mining within the different regions', 221::int),
    ('GRY 004', 15, NULL, NULL, 'Industry', '• Industrial development and industrial regions in Nigeria, West Africa, Africa and North America;
• Importance and problems of each region;', 221::int),
    ('GRY 004', 16, NULL, NULL, 'Trade and Transport', '• Trade Flows, Trading Patterns and transportation', 221::int),
    ('GRY 004', 17, NULL, NULL, NULL, 'networks within and between the regions;
• The World Trade Organization (WTO) – meaning and importance;
• Economic Transition (National Development, Globalization of Economic Activities) in Nigeria.', 222::int),
    ('GRY 004', 18, '8', 'Environmental Resources Management', 'Environmental Resources', '• Meaning of Environmental Resources;
• Classification of Environmental Resources (Natural, Human, Renewable & Non-Renewable).
• Types of Environmental Resources -Atmospheric, water, vegetation, mineral, soil, and energy resources) within Nigeria, West Africa, Africa and North America;
• Importance of Environmental Resources.', 222::int),
    ('GRY 004', 19, NULL, NULL, 'Challenges & Management of Environmental Resources', '• Challenges of the different types of environmental resources in each region (e.g. Deforestation, desertification, pollution, and resource depletion, effects of technology and population density, etc);
• Sustainable management strategies and Conservation of environmental Resources in Nigeria, West Africa, Africa, and North America (e.g. adopting the Principles of sustainability;', 222::int),
    ('GRY 004', 20, NULL, NULL, NULL, 'conservation measures and policies; international cooperation, etc.).', 223::int),
    ('GRY 004', 21, '9', 'Field Studies', 'Local Fieldwork & Report', 'Study of physical and human features of the local environment. This will involve data collection, analysis and reporting', 223::int),
    ('GOV 001', 1, '1', 'Basic Concepts and Nature of Government and Politics', 'Definitions of government and politics, Rationale for studying government as an academic discipline, .', 'The candidates are expected to have deep knowledge and understanding of government and politics for general application to issues in the political structure, institutions and processes. Power, Influence, Authority, Legitimacy, Sovereignty, Nation, State, Nation-State, Political Culture, Political Socialization, Political Participation', 227::int),
    ('GOV 001', 2, '2', 'Scope and relationship with other disciplines', NULL, 'The candidates are expected to understand the meaning and nature of:
i. Political Theory ii. Political Economy iii. International Relations iv. Public Administration v. Local Government vi. Comparative Politics vii. Peace and Conflict Studies viii. Security Studies and Development Studies.', 227::int),
    ('GOV 001', 3, NULL, NULL, 'Relationship between the study of government/politics and other academic disciplines.', 'i. History ii. Philosophy iii. Law iv. Economics v. Geography vi. Sociology/ anthropology vii. Psychology', 228::int),
    ('GOV 001', 4, '3', 'Methods/Approaches to the Study of government and politics.', 'i. Philosophical/Nor mative ii. Institutional/legal iii. Historical iv. Comparative v. Qualitative vi. Quantitative vii. Scientific viii. Behavioural ix. Empirical.', 'Arguments on the scientific status of politics.', 228::int),
    ('GOV 001', 5, '4', 'The State, Structure and Types of Government', 'Definition, Purpose and Functions of the Modern state, Theories of the State, Characteristics of the State, Types of State.', NULL, 228::int),
    ('GOV 001', 6, NULL, NULL, 'Structure of Government', 'i. Executive ii. Legislature iii. Judiciary', 228::int),
    ('GOV 001', 7, NULL, NULL, 'Functions, relationships, strengths and weaknesses of the executive, legislature and judiciary.', NULL, 228::int),
    ('GOV 001', 8, NULL, NULL, 'Types of government.', 'i. Democracy ii. Monarchy iii. Oligarchy iv. Aristocracy v. Military vi. Theocracy vii. Gerontocracy viii. Plutocracy', 229::int),
    ('GOV 001', 9, NULL, NULL, 'Systems of Government.', 'i. Presidential ii. Parliamentary iii. Republican iv. Unitary v. Federal vi. Confederal', 229::int),
    ('GOV 001', 10, NULL, NULL, 'Differences between government and governance.', NULL, 229::int),
    ('GOV 001', 11, '5', 'Constitution and Constitutionalism', 'Definition of Constitution', NULL, 229::int),
    ('GOV 001', 12, NULL, NULL, 'Types of Constitution', 'i. Written and Unwritten ii. Unitary and Federal iii. Flexible and Rigid.', 229::int),
    ('GOV 001', 13, NULL, NULL, 'Objectives of a Constitution', 'i. Empowering States ii. Establishing values and goals iii. Providing Government stability iv. Protecting freedom and Legitimizing regimes.', 229::int),
    ('GOV 001', 14, NULL, NULL, 'Definition of Constitutionalism', NULL, 229::int),
    ('GOV 001', 15, NULL, NULL, 'Features of Constitutionalism', 'i. Rule of law ii. Separation of Powers iii. Supremacy of the Constitution iv. Fundamental Human Rights v. Independence of the Judiciary vi. Checks and Balances', 230::int),
    ('GOV 001', 16, NULL, NULL, 'The relationship between Constitution and Constitutionalism.', NULL, 230::int),
    ('GOV 001', 17, '6', 'Citizenship', 'Meaning of citizenship, Ways of acquiring citizenship, Rights of citizens, Duties and obligations of citizens.', NULL, 230::int),
    ('GOV 002', 1, '1', 'Political ideologies and theories', 'The meaning, nature, types and functions of ideology. Political theories', 'i. Communalism ii. Feudalism iii. Capitalism and Imperialism iv. Fascism and Nazism v. Marxism, Socialism and Communism vi. Conservatism vii. Liberalism viii. Authoritarianism ix. Totalitarianism x. Anarchism i. Social Contract theories ii. Utilitarianism iii. Feminism iv. Environmentalism', 231::int),
    ('GOV 002', 2, '2', 'Political Parties, Party systems and Pressure Groups', 'Definitions and Functions of Political Parties; Organs of Political Parties Types of Political Parties, Meaning and types of Party system, Relationship between Party Systems and Political Parties,', NULL, 231::int),
    ('GOV 002', 3, NULL, NULL, 'Meaning, Types and Functions of Pressure Groups, Modes of operation of Pressure Groups', 'Comparison between Political Parties and Pressure Groups.', 232::int),
    ('GOV 002', 4, '3', 'Public Opinion and Propaganda', 'Definition, Functions and Measurement of Public Opinion, Meaning and Nature of Propaganda, Function and Strategies of Propaganda.', NULL, 232::int),
    ('GOV 002', 5, '4', 'Elections and Electoral Systems', 'Definition of Election, Purpose of Elections.', NULL, 232::int),
    ('GOV 002', 6, NULL, NULL, 'Types of elections', 'i. Primary election ii. General election iii. Bye-election iv. Run-off election etc.', 232::int),
    ('GOV 002', 7, NULL, NULL, 'Meaning, Evolution and types of Suffrage, Meaning, conditions and factors militating against the conduct of free and fair election, Meaning and types of electoral systems, Historical background of elections in Nigeria,', NULL, 232::int),
    ('GOV 002', 8, NULL, NULL, 'Election management bodies in Nigeria.', 'i. FEDECO ii. NECON iii. NEC iv. INEC.', 232::int),
    ('GOV 002', 9, NULL, NULL, 'General Elections in Nigeria.', 'i. 1959 ii. 1964 iii. 1979 iv. 1983 v. 1993 vi. 1999 vii. 2003 viii. 2007 ix. 2011 x. 2015 xi. 2019 and 2023.', 233::int),
    ('GOV 002', 10, NULL, NULL, 'Problems of Elections in Nigeria', NULL, 233::int),
    ('GOV 002', 11, '5', 'Public Administration', 'Meaning of public administration, Differences and similarities between public and private administration,', NULL, 233::int),
    ('GOV 002', 12, NULL, NULL, 'Theories of Public Administration', 'i. Administrative theory ii. Scientific management theory iii. Bureaucratic theory iv. Human relation theory', 233::int),
    ('GOV 002', 13, NULL, NULL, 'Characteristics and functions of the Civil Service.', NULL, 233::int),
    ('GOV 002', 14, NULL, NULL, 'The Policy Process.', 'i. Formulation ii. Implementation and iii. Evaluation.', 233::int),
    ('GOV 002', 15, NULL, NULL, 'Meaning, functions and challenges of public corporations in Nigeria, Meaning, functions and challenges of the local government in Nigeria.', NULL, 233::int),
    ('GOV 002', 16, '6', 'International Relations', 'Meaning of International Relations, Difference between International Relations and International Politics, Meaning and Objectives of Foreign Policy, Determinants of Foreign Policy in Nigeria, Meaning and impact of globalization.', NULL, 234::int),
    ('GOV 002', 17, NULL, NULL, 'History, Structure, Achievements and Failures of International Organizations.', 'i. ECOWAS ii. African Union iii. Commonwealth of Nations iv. United Nations v. International Monetary Fund (IMF) and vi. World Bank.', 234::int),
    ('GOV 003', 1, '1', 'Pre-colonial, Colonial and Post-Colonial Systems of Government in Nigeria', 'The system of government in pre-colonial Hausa/Fulani, The system of government in pre-colonial Yoruba, The system of government in pre-colonial Igbo. Amalgamation of Northern and Southern Nigeria in 1914, Constitutional Development in Nigeria: 1922-1960, Indirect Rule in Nigeria, The growth and effects of Nationalism in Nigeria, Constitutional Development in Nigeria: 1960 to Present.', 'At the end of the course the students should be able to explain the pre-colonial and colonial histories of Nigeria.', 235::int),
    ('GOV 003', 2, '2', 'Foundations of Nigerian legal system', 'Nature of legal administration and judicial processes in Nigeria; Sources of the Nigerian laws; Hierarchy and powers of the courts; Administration of Justice (military and democracy)', 'Sources of Nigerian laws: English Law, English Received Laws, Customary Laws, Judicial Precedents and many others', 235::int),
    ('GOV 003', 3, '3', 'Development of Political Parties in Nigeria', 'Colonial and First Republic Political Parties.', 'i. Nigerian National Democratic Party (NNDP) ii. Nigerian Youth Movement (NYM) iii. National Council of Nigeria and Cameroons (NCNC) iv. Action Group (AG) v. Northern Peoples’ Congress (NPC) vi. NEPU, UMBC, NNDP, NDC, UNIP', 236::int),
    ('GOV 003', 4, NULL, NULL, 'Second Republic Political Parties.', 'i. National Party of Nigeria (NPN) ii. Unity Party of Nigeria (UPN) iii. Nigeria Peoples’ Party (NPP) iv. Great Nigeria Peoples’ Party (GNPP) v. Peoples’ Redemption Party (PRP) vi. Nigeria Advance Party (NAP)', 236::int),
    ('GOV 003', 5, NULL, NULL, 'Third Republic Political Parties.', 'i. National Republican Convention (NRC) ii. Social Democratic Party (SDP)', 237::int),
    ('GOV 003', 6, NULL, NULL, 'Fourth Republic Political Parties.', 'i. All Peoples’ Party (APP) ii. Peoples’ Democratic Party (PDP) iii. Alliance for Democracy (AD) iv. Action Congress of Nigeria (ACN) v. Congress for Progressive Change (CPC) vi. All Progressives Congress (APC) All Progressive Grand Alliance (APGA), etc.', 237::int),
    ('GOV 003', 7, '4', 'Major Issues in Nigerian Government and Politics', 'Aba women uprising of 1929, the Kano riots 1953, Action Group crisis of 1962, the census crises, Nigerian-Biafra civil war of 1967 to 1970, challenges of federalism and Ethno-religious crises.', NULL, 237::int),
    ('GOV 003', 8, NULL, NULL, 'Electoral crises in Nigeria.', 'June 12 1993, 2011 post-election violence', 237::int),
    ('GOV 003', 9, NULL, NULL, 'Niger Delta crisis, Boko Haram terrorism, Farmer-Herder conflicts, banditry, separatist agitations', NULL, 237::int),
    ('GOV 003', 10, '5', 'Military Intervention in Nigerian Politics', 'Characteristics of Military rule in Nigeria, Reasons for Military Intervention', 'The Military Regimes of Ironsi, Gowon, Muritala, Obasanjo,', 237::int),
    ('GOV 003', 11, NULL, NULL, 'Disengagement of Military from Politics: Transition Programmes, Achievements and Failures of Military Rule in Nigeria, Panacea to preventing military intervention in Nigerian politics', 'Buhari/Idiagbon, Babangida, Abacha, and Abdulsalami Abubakar.', 238::int),
    ('GOV 004', 1, '1', 'Africa before European Invasion', 'Major contributions of Africa to the world civilization before European Invasion.', 'At the end of the course the students should be able to explain i. Africa before European invasion ii. Contribution of manpower for building the new world', 238::int),
    ('GOV 004', 2, NULL, NULL, NULL, 'iii. Development of the writing technology iv. European invasion of Africa v. Colonial systems of administration in Africa vi. The nationalist movement in West Africa and critical issues in African government and politics', 239::int),
    ('GOV 004', 3, NULL, NULL, 'Establishment and maintenance of self-reliant political empires such as Ghana, Mali and Songhai empires as well as Zulu, Kanem-Bornu and Benin kingdoms', 'Discuss the origin, evolution, reasons for rise, and reasons for the falls of each empire', 239::int),
    ('GOV 004', 4, '2', 'European invasion of Africa', 'Strategies of European invasion of Africa', 'i. Slave trade ii. Legitimate trade iii. Missionaries iv. Colonialism v. Treaties of friendship and Protection vi. Military Conquests (Wars)', 239::int),
    ('GOV 004', 5, NULL, NULL, 'Reasons for European Expansion to Africa, The Scramble for and Partitioning of Africa (emphasis on Berlin Conference -1884-1885), Apartheid Regime in South Africa', NULL, 239::int),
    ('GOV 004', 6, NULL, NULL, 'African Responses to European invasion', 'i. Invasion ii. Resistance iii. Negotiations iv. Settlement of Europeans', 240::int),
    ('GOV 004', 7, NULL, NULL, 'Meaning, origin and manifestations of Neocolonialism in Africa', 'Problems of neocolonialism and dependency', 240::int),
    ('GOV 004', 8, '3', 'Colonial Systems of Administration in Africa', 'Indirect Rule System, Policies of Assimilation and Association', NULL, 240::int),
    ('GOV 004', 9, '4', 'The Nationalist Movements in West Africa', 'Nationalist Movements in British West Africa, Nationalist Movements in French West Africa', 'Nationalist Movement British West Africa:
NCBWA, WASU and NYM Nationalist Movement for French West Africa:
Negritude Movement, Blaise Diagne Movement, African Democratic Rally, Senegalese Progressive Union', 240::int),
    ('GOV 004', 10, '5', 'Critical Issues in African Government and Politics', 'Democratization, Human Rights Violations, Ethnicity, Poverty, Leadership problems, illicit financial flow, Structural adjustment problem, Debt crisis, Migration, Human Trafficking, Insecurity and climate change in Africa.', NULL, 240::int),
    ('AGR 001', 1, '1', 'Soil Physics, Soil Chemistry and Soil Biology', 'Soil physical properties', 'Definition, Soil formation, Weathering processes, composition and soil physical properties e.g. soil texture, soil structure, soil capillarity, bulk density, porosity, soil color etc.', 246::int),
    ('AGR 001', 2, NULL, NULL, 'Soil Chemical Properties', 'Soil acidity and alkalinity; causes and effects on crops, soil Ph, cation exchange capacity (ECE) and Anion Exchange Capacity (AEC). Correction of soil acidity', 246::int),
    ('AGR 001', 3, NULL, NULL, 'Soil Fertility', 'Soil macro elements (N, P, K, etc.) and micro nutrients (Mo, B, Zn, etc.). Nitrogen Cycle. Organic matter composition and importance to agriculture. Soil improvement through the application of Organic fertilizers.', 247::int),
    ('AGR 001', 4, '2', 'Soil & Water Conservation', 'Soil and Water Conservation Methods', 'Definition, methods and importance of soil conservation. Methods of controlling soil erosion (biological, mechanical and cultural). Methods of water conservation (dams, harvesting from roofs water weirs, mulching).', 247::int),
    ('AGR 001', 5, NULL, NULL, 'Irrigation', 'Types of irrigation systems (surface, overhead and underground systems). Importance of irrigation to agricultural production in Nigeria.', 247::int),
    ('AGR 001', 6, '3', 'Crop Plant Genetics', 'Plant growth, development and improvement', 'Study of the cell and its contents. Cell division and enlargements leading to growth (mitosis). Meiosis, pollen structure, pollen formation and ovule development. Seed dormancy, pre-germination treatment, viability test, control and seed germination experiments. Mendelian laws of inheritance and processes of crop improvement.', 247::int),
    ('AGR 001', 7, '4', 'Crop Plant Metabolism, Anatomy and Physiology', 'Water and Nutrient Uptake', 'Mechanism of water uptake (Osmosis/Diffusion) and nutrient uptake, (Active transport system).', 248::int),
    ('AGR 001', 8, NULL, NULL, 'Plant Anatomy, Photosynthesis and Respiration', 'Plant parts identification. Meaning and importance of photosynthesis, factors affecting photosynthesis e.g. carbon (IV) oxide, compensation point. Relationship between respiration and photosynthesis. Role of Adenosine Triphosphate (ATP) as the energy currency in all living organisms.', 248::int),
    ('AGR 001', 9, '5', 'Crop Husbandry', 'Principles of Crop Protection', 'Identification and classification of common weeds, methods of weed control. Identification and classification of common pests and diseases. Control methods of pests and diseases.', 248::int),
    ('AGR 001', 10, NULL, NULL, 'Principles of Horticultural Crop Production', 'Definition of horticulture. Classification of Horticultural plant, economic importance of horticulture and ornamental crop production in Nigeria, discuss one ornamental plant (rose or hibiscus) under the following headings:
Origin, Methods of Cultivation, Land Preparation, Management Practices, Pests and Diseases Control, Factors Affecting Shelf Life, Post-Harvest Handling and Marketing.', 248::int),
    ('AGR 001', 11, NULL, NULL, 'Principles of Crop Production', 'Growth and study of horticultural crops (mango or orange), field crops (maize, rice,cowpea,soyabean)and vegetable crop (Amaranthus spp). Under the following headings: Origin, Adaptation, Planting, Management, Pests and Diseases Control, Post-Harvest Handling and Marketing. Vegetative propagation methods (budding, grafting, layering, marcotting, & cutting).', 249::int),
    ('AGR 001', 12, '6', 'Agricultural Engineering', 'Farm Mechanization', 'Definition of Farm Mechanization, Advantages and Disadvantages of Farm Mechanization, Operational Principles and Maintenance of the two and four Stroke Cycle Engines, Properties and Use of Fuel and Lubricants, Transmission Systems, Electrical Systems of Petrol and Diesel Engines, Tillage Implements (ploughs, ridgers, harrows).', 249::int),
    ('AGR 001', 13, NULL, NULL, 'Animal Power and Animal Drawn Implement', 'Types of draught animals (Bull, donkey, horse). Animal drawn implements (Mouldboard plough, harrow, & planter). Select a draught animal, calculate the draught force requirement, angle of attack and angle of inclination of a mouldboard plough; etc.', 249::int),
    ('AGR 002', 1, '1', 'Animal Production', 'Animal husbandry', 'Forms and classification of major farm animals in West Africa, General terminology in animal production, Anatomy of farm animal, Livestock Management.', 250::int),
    ('AGR 002', 2, '2', 'Animal Metabolism', 'Animal Nutrition', 'Classes of livestock feed(Roughages, succulents, concentrates). Feed digestibility and calculation of feed digestibility. Feed ration and ration formulation.', 250::int),
    ('AGR 002', 3, '3', 'Reproduction in Farm Animals', 'Physiology of Farm Animals', 'Urinogenital systems of farm animals. Fertility and infertility in Farm Animals (male and female).Site of fertilization in female farm animals.', 250::int),
    ('AGR 002', 4, '4', 'Animal Genetics', 'Animal Breeding', 'Mendelian Laws of Heredity. Inbreeding and Crossbreeding:
Advantages and Disadvantages. Improvement of farm animals. Terminologies in animal breeding.', 250::int),
    ('AGR 002', 5, '5', 'Animal Pathology and Control', 'Animal Health', 'Identification and Classification of Important Parasites and Diseases of Farm Animals. Economic Importance of Diseases and Parasites of Farm Animals. Pests and Disease Transmission and Control.', 251::int),
    ('AGR 002', 6, '6', 'Animal Products', 'Uses of Animal Parts', 'Processing, Storage and Marketing of fish, meat, egg, milk, wool, leather etc.', 251::int),
    ('AGR 003', 1, '1', 'Social, Economic and Environmental Forestry', 'Importance of Forestry and Wildlife to the Nigerian Economy.', 'Definition of forestry, Economic, social and ecological importance of wildlife and forests.', 251::int),
    ('AGR 003', 2, '2', 'Principles of Agroforestry', 'Important Agroforestry Systems in Nigeria', 'Definition, principles and types of agroforestry. Concept of forest, forestry and silviculture. Definition and practice of agroforestry. Systems of agroforestry (e.g. Agrosilvipastoralism, Agrosilviaquaculture, Agrosilviapiculture, Agrosilvimycology, Agrosilviheliculture, etc.,). The need for conserving our forests (sources of useful medicinal herbs, dyes, fibres, game animals which energize our rural economy).', 252::int),
    ('AGR 003', 3, '3', 'Forestry and Climate Change', 'The Roles of Forestry on Climate Change Mitigation', 'Definition of climate change. Causes, Mitigation and Adaptation to Climate Change. Effects of Climate Change on Agriculture.', 252::int),
    ('AGR 003', 4, '4', 'Forest, Wildlife, Ecotourism and Management', 'Wildlife and Forest Conservation/ Management', 'Meaning of Wildlife, forestry Wildlife Conservation Methods. Ecotourism potentials of Forest and Wildlife in Nigeria. Identification and Classification of Common Species of Wild Animals and Trees in Nigeria.', 252::int),
    ('AGR 003', 5, NULL, NULL, NULL, 'Selective exploitation, Forest regulation, Afforestation, Regeneration, Taungya system, Enrichment planting, etc.', 253::int),
    ('AGR 003', 6, '5', 'Deforestation and Desertification', 'Mitigation of Deforestation and Desertification in Nigeria', 'Meaning of Deforestation and Desertification. Causes of Deforestation and Desertification. Effects of Deforestation, Desertification and control.', 253::int),
    ('AGR 003', 7, '6', 'Timber and Non-Timber Forest Products', 'Utilization of Forest Resources', 'Shelter for wildlife, sources of cooking fuel, raw materials for industries e.g. plywood, etc.', 253::int),
    ('AGR 003', 8, NULL, NULL, 'Marketing of Forest Products', 'Types of Forest Products and examples. Harvesting(timber),Processing, marketing and exportation of the forest products.', 253::int),
    ('AGR 003', 9, '7', 'Aquaculture, Environment and Economy', 'Fish Production and Its Environment', 'Types of fish and fish ponds. Methods of fish pond construction. Importance of fish production to Nigerian economy. Fish culture, fish processing, fish preservation, toxicology, availability of markets. Laws and regulations on fishing.', 253::int),
    ('AGR 004', 1, '1', 'Principles of Agricultural Economics', 'Demand and Supply of Agricultural Goods and Services', 'Definition of Agricultural Economics, Principles of demand and supply of agricultural products, simple demand and supply curves, illustration with diagrams, the elasticity of demand and supply. Law of diminishing returns, principles of economies of scale in agriculture and opportunity costs.', 254::int),
    ('AGR 004', 2, '2', 'Agricultural Extension and Management', 'Principles of Agricultural Extension', 'Definition and Objectives of Agricultural Extension. Functions and principles of Agricultural Extension. Role of extension agents, methods of', 254::int),
    ('AGR 004', 3, NULL, NULL, NULL, 'dissemination of improved technology; Agricultural Extension methods. Problems of effective extension programmes in Nigeria. Basic concepts and principles of rural sociology. Importance of rural communities and institutions, social stratification, social processes, and social changes in rural areas. Emergence and functions of leadership in rural communities. Agricultural extension teaching methods, aids, and their use.', 255::int),
    ('AGR 004', 4, '3', 'Farm Management', 'Land Tenure, Risk, Uncertainty and Budgeting in Agri-Business', 'Land tenure systems in Nigeria and their implications to agriculture. Land use act of 1978, Business objectives in farming, risks and uncertainties in agriculture, budgeting in farming business.', 255::int),
    ('AGR 004', 5, '4', 'Agricultural Marketing', 'Marketing of Agricultural Produce', 'Definition of agricultural marketing, characteristics of perfect and imperfect competition. Type of markets, perfect competition, monopoly, oligopoly etc. International trade agreements and their impact on marketing. Problems of marketing agricultural produce. Government intervention programmes in agriculture (support prices and subsidies). Cost analysis', 255::int),
    ('AGR 004', 6, NULL, NULL, NULL, 'and functions. Concept of elasticities. Price theory and some applications. The components of agriculture in national income. Aggregate income, expenditure, investment, interest rate, savings, employment. Inflation; international trade, commodity agreements, and balance of payments. Money and banking.', 256::int),
    ('AGR 004', 7, '5', 'Agricultural Accounting and Finance', 'Importance of Agricultural Accounting and Finance', 'Definition of agricultural accounting and finance; Importance of farm accounting and finance, common sources of farm credit, subsidy, loan, etc.', 256::int),
    ('AGR 004', 8, '6', 'Principles of Family and Consumer Sciences, Food Science and Technology', 'Historical development of family and consumer science', 'Philosophy, scope, objectives and historical development of family and consumer sciences. Examination of basic human needs with respect to food, clothing, shelter, and health. Programme approaches in family and consumer sciences which will help meet these needs. Professional opportunities in family and consumer sciences. The role of a family and consumer sciences professional in today''s society. Definition and scope of food science and technology. Food distribution and marketing. Food and its functions. Food habits. Food', 256::int),
    ('AGR 004', 9, NULL, NULL, NULL, 'poisoning and its prevention. Principles of food processing and preservation. Discussion of different preservation methods. Deterioration and spoilage of foods, other post- harvest changes in food. Contamination of foods from natural sources. Composition and structures of Nigerian/West African food; factors contributing to texture, colour, aroma, and flavour of food. Cost, traditional and ethnic influence of food preparation and consumption pattern.', 257::int),
    ('BIO 001', 1, '1', 'Origin of Living Things', 'The Science of Biology', 'Definition of biology Branches of biology Importance of biology The nature of science
- Scientific methods
- Observation
- Recording
- Testing of hypothesis
- Data collection and analysis Application of scientific methods in biological experiments Relationship between Biology & Medicine, Agriculture, etc. Brief history of organic molecules', 261::int),
    ('BIO 001', 2, NULL, NULL, 'Origin of Organic Molecules', 'Brief history of organic molecules.', 261::int),
    ('BIO 001', 3, NULL, NULL, 'Origin of the First Cells', 'Brief history of the evolution of the first cells', 262::int),
    ('BIO 001', 4, NULL, NULL, 'The Earliest Cells: -Living -Fossils', 'Relate the living cell to the fossil', 262::int),
    ('BIO 001', 5, NULL, NULL, 'Basic biostatistics', 'Definition of basic biostatistics Central tendency measurement', 262::int),
    ('BIO 001', 6, '2', 'Living Things in Nature and Biological Molecules', 'Diversity of Living Things', 'Different kingdoms and characteristics.', 262::int),
    ('BIO 001', 7, NULL, NULL, NULL, 'Practical class- Field observation of diversity of living things', 262::int),
    ('BIO 001', 8, NULL, NULL, 'Biological Molecules', 'Carbohydrate, lipids, protein and nucleic acids (DNA and RNA)', 262::int),
    ('BIO 001', 9, '3', 'Cell Organisation, Structure and Functions', 'Cell Theory, Cell Structure and Functions', 'Demonstration of cell structure on microscopes.', 262::int),
    ('BIO 001', 10, NULL, NULL, 'Cell Organization, Forms in which Cells Exist', 'Biological drawings of plant and animal cells. Comparisons of plant and animal cells', 262::int),
    ('BIO 001', 11, '4', 'Cell Division, Principles of Genetics, Variations and Heredity', 'Cell Divisions, Mitosis in Somatic Cells, Meiosis in Germ Cells, Principles of Genetics Variation and Heredity', 'Definition, Cell cycle, Basic concepts in genetics :
Chromosome, Gene, allele, dominant, recessive, Homozygous, Heterozygous, Hybrid, genotype, phenotype etc', 262::int),
    ('BIO 001', 12, NULL, NULL, 'Mendel’s Laws of Inheritance', 'The nature of genes and chromosomes Mendelian Genetics', 262::int),
    ('BIO 001', 13, NULL, NULL, NULL, 'Practical class:
Determination of inheritance using coloured seeds e.g. beads, grains, etc. Verifications of principles of Mendel’s law and its deviation', 262::int),
    ('BIO 001', 14, NULL, NULL, 'Human Inheritance, Human Genetic Disorders e.g. sickle cell anemia, albinism. Rhesus Factors, Polyploidy, Sex-linked Traits; Application of Genetics in Agriculture, Medicine, Criminology, etc.', 'Cell division experiment using onion root. Identification of stages of meiosis, Traits controlled by Multiple alleles e.g. blood group, eye colour. Determination of inheritance using coloured seeds e.g. beads, grains etc. Verifications of principles of Mendel’s laws. Pedigree symbols and applications', 263::int),
    ('BIO 001', 15, '5', 'Systematics, Taxonomy and Nomenclature', 'Basis of Taxonomy Rules of Systematics Naming of Organisms (Nomenclature)', 'Criteria for classification Taxonomy hierarchy Binomial nomenclature: Genus & species Practical class:
Classification and identification of organisms, Highlighting adaptive features and their uses', 263::int),
    ('BIO 001', 16, '6', 'Ecology', 'Basic Concepts in Ecology', 'Ecosystem, food chain, food web, nutrient cycling, biogeochemical cycles', 263::int),
    ('BIO 001', 17, NULL, NULL, 'Biological Associations and Interactions', 'Symbiosis, Mutualism, Parasitism, Commensalism, Ammensalism & Synergism', 263::int),
    ('BIO 001', 18, NULL, NULL, 'Ecology Studies, Types of Habitats', 'Environmental studies', 263::int),
    ('BIO 001', 19, NULL, NULL, NULL, 'Practical use of ecological equipment, Population study in a specific habitat', 263::int),
    ('BIO 001', 20, NULL, NULL, 'Ecology and Natural Selection.', 'Environmental changes Ecological Adaptation: Definition of Adaptation, types of Ecological Adaptations:
Structural /Morphological Adaptation, Physiological Adaptation,', 263::int),
    ('BIO 001', 21, NULL, NULL, NULL, 'Behavioral Adaptation, Habitat/Ecological Adaptation (Xeric, Hydrophytic, Mesophytic, Halophytic, Epiphytic), Reproductive, Mimicry/Camouflage, Biochemical Adaptations. Biological impacts of climate change', 264::int),
    ('BIO 001', 22, '7', 'Biological Methods and Application', 'Rules of Biological Drawings', 'Standard drawing rules governing: use of pencils, specimen proportions, magnification, size of specimen drawing and labelling:
Diagrams must be according to length specification, Lines must not be woolly or broken. Drawings must carry appropriate titles at the correct position Labelling must be horizontal & parallel with ruled guidelines Drawing must not be artistic i.e. no shading or painting. Spellings must be correct and touched by labelling lines.', 264::int),
    ('BIO 001', 23, '8', 'Evolution', 'Geological Times, and Mega Geological Events, Evolutionary Trends in Animals and Plants, Theories of Evolution- Lamarck and Darwin Theories of Evolution. Evidence of evolution from Anatomy, Embryology, Biochemistry.', 'Definition of evolution, Types of evolution, Application of Evolution to Plants & Animals Taxonomy.', 264::int),
    ('BIO 001', 24, '9', 'Enzymes', 'Properties of Enzymes, Mechanism of Enzyme Reaction, Enzyme Inhibition & Enzyme Cofactors', 'Enzymes, Types of enzymes & Factors affecting rate of enzyme action', 265::int),
    ('BIO 002', 1, '1', 'General Characteristics and Diversity of Plants', 'Characteristics of Lower and Higher Plants groups', 'Classification of major plant groups (Lower and Higher plants) Divisions up to generic level Lower plants- algae, fungi, Bryophytes, Pteridophytes', 265::int),
    ('BIO 002', 2, NULL, NULL, 'Morphology and Life Cycle of Lower and Higher Plants', 'Morphological and life cycle of named example in each major group considering the simplest and the complex in each group of the lower plants. Economic and ecological importance of plant groups', 265::int),
    ('BIO 002', 3, NULL, NULL, NULL, 'Practical class classification and morphological drawings of lower plants :
Algae (Chlorella, Euglena/Chlamydomonas, Volvox, Spirogyra) Fungi e.g. yeast, Rhizopus, Mucor, Aspergylus, Penicillium, mushroom, Phytophthora, Bryophytes e.g. Riccia, Marchantia, Funaria Pteridophytese.g. Lycopodium, Seleginella, Nephrolepis Higher plant (Non-vascular and vascular plants) Spermatophytes e.g. Cycas, Pinus, Gnetum, Hibiscus rosa-sinensis', 266::int),
    ('BIO 002', 4, NULL, NULL, 'Morphology of Eleusine indica and Morphology of Talinum triangulare', 'Eleusine indica and Talinum triangulae treated comparatively', 266::int),
    ('BIO 002', 5, '2', 'Taxonomy of Lower and Higher Plants', 'Plant Taxonomy and Systematics Taxonomy of Lower and Higher Plants', 'Definition, Plant nomenclature, Plant classification & the difference between Taxonomy and Systematics.', 266::int),
    ('BIO 002', 6, '3', 'Plant Conservation', 'Importance of Plant Conservation Measures in Plant Conservation Climate change', 'Definition, concepts in plant conservation, In-situ and ex-situ conservation. Advantages and disadvantages of each: Biological control, Pest management, Impact of climate change on plants', 266::int),
    ('BIO 002', 7, '4', 'Plant Tissues and Functions', 'Plant Tissues and Functions Plant Tissues Anatomy & Functions', 'Emphasis on composition, distribution, forms and functions of each tissues: Epidermal, Peridermal, Parenchyma,', 266::int),
    ('BIO 002', 8, NULL, NULL, NULL, 'Collenchyma, Schlerenchyma, Epidermal, Peridermal, Vascular (cambium, phloem, xylem)', 267::int),
    ('BIO 002', 9, '5', 'Plant Morphology/ Anatomy', 'Morphology of Plant Parts', 'Morphology of roots, stems fruits and , leaf types and their modification due to functions', 267::int),
    ('BIO 002', 10, NULL, NULL, 'Anatomy of Plant Parts.', 'Anatomy of monocot and dicot roots, stems and leaves with emphasis on tissue arrangement in relation to functions and environment', 267::int),
    ('BIO 002', 11, NULL, NULL, 'Types of Root', 'Practical class Roots-
- Adventitious and tap root systems, modification and adaptations
- Anatomical observation and drawing of permanent/ temporary mount of monocot and dicot roots (T.S and L.S)
- Locate, draw and label different plant tissues (parenchyma, collenchyma etc)', 267::int),
    ('BIO 002', 12, NULL, NULL, 'Types of Stem', 'Stem:
- Aerial and underground stem, modifications/ adaptations related to functions
- Anatomical observation and drawing of permanent/ temporary mount of monocot and dicot stems (T.S and L.S)
- Locate, draw and label different plant tissues (parenchyma, collenchyma etc)', 267::int),
    ('BIO 002', 13, NULL, NULL, 'Types of Leaves', 'Leaves
- Simple and compound leaves, arrangements, modifications to suit habitats
- T.S of leaves of both monocot and dicot plants Locate, draw and label different plant tissues (parenchyma, collenchyma etc)', 268::int),
    ('BIO 002', 14, NULL, NULL, 'Types of Flowers', 'Flowers
- L.S of dicot flowers e.g. regular and irregular flowers, floral diagrams and formula', 268::int),
    ('BIO 002', 15, NULL, NULL, 'Types of Fruits', 'Fruits
- L.S and T.S of various types of fruits (dry dehiscent, indehiscent and fleshy fruits should be observed and drawn).', 268::int),
    ('BIO 002', 16, '6', 'Nutrition in Plants', 'Nature and Types of Nutrition', 'Autotrophic (photosynthetic and chemosynthetic), Dark and light reaction in photosynthesis, Heterotrophic & Holozoic nutrition, Mineral requirements of plants, their sources, roles and deficiency symptoms. Composition of chemical fertilizers', 268::int),
    ('BIO 002', 17, NULL, NULL, NULL, 'Practical class:
Demonstration of etiolation. Measurement of photosynthesis in leaf Growth experiments to show deficiency symptoms Field study of deficiency symptoms in plants', 269::int),
    ('BIO 002', 18, '7', 'Transport System in Plants', 'Transport System in Plants Need for Transport System Water Relation', 'Mineral requirements of plants Transport in xylem Transport in phloem Transport media in plant and materials to be transported', 269::int),
    ('BIO 002', 19, NULL, NULL, NULL, 'Practical class -Transpiration, osmosis, diffusion and food transport in plants', 269::int),
    ('BIO 002', 20, '8', 'Respiration', 'Mechanism of Gaseous Exchange', 'Stomata apparatus, Lenticels, Aerobic and anaerobic respiration', 269::int),
    ('BIO 002', 21, '9', 'Plant reproduction', 'Asexual and Sexual Reproduction', 'Definition, Asexual reproduction, Types of asexual reproduction, Vegetative propagation. Sexual reproduction in flowering plants, Angiosperm flower and differences between monocots and dicot flowers', 269::int),
    ('BIO 002', 22, '10', 'Growth in Higher Plants and growth Regulators', 'Plant growth, Roles and Interactions of Growth Regulators', 'Growth in the roots and shoots Auxins, Gibberellins, Cytokinins, Ascorbic acids, Ethylene', 269::int),
    ('BIO 002', 23, '11', 'Crop improvement', 'Importance of Genetically Modified Crops (GMC)', 'Genetically Modified Crops (GMC) Challenges of resistant plant species, Ethical implications of genetic modifications', 269::int),
    ('BIO 002', 24, '12', 'Economic and Ecological Importance of Plants', 'Plants of Economic & Medical Importance', 'Economically important food plants, Economically valuable medicinal plants& Ornamental plants', 270::int),
    ('BIO 003', 1, '1', 'History of the Discovery of Microorganisms', 'Spontaneous Generations Microorganisms as the Cause of some Diseases', 'The theory of spontaneous generation of organisms, Conflict over spontaneous generations, The golden era of microbiology (1860-1910), The germ theory of disease, The discovery of viruses, microorganisms in the 20th century', 270::int),
    ('BIO 003', 2, NULL, NULL, NULL, 'Practical class Introduction to basic microbial laboratory equipment, principles of operation and drawings', 271::int),
    ('BIO 003', 3, '2', 'Types and Taxonomic Groupings of Microorganisms', 'Seven Levels of Classification Prokaryotic Cells Eukaryotic Cells', 'Bacteria- size, shapes, motility, unusual types, general methods of bacterial classification. Fungi- yeast and mould- size, shape, general fungal classification Protozoa- specific examples, motile and non-motile types, nutrition types. Viruses- sizes, bacteriophages, viroid, prions, Algae- sizes, types, diatoms, sea weeds, lichens, sexual and asexual reproduction Archaea- general features, origin and evolution', 271::int),
    ('BIO 003', 4, NULL, NULL, NULL, 'Practical class Aseptic techniques in microbiology', 271::int),
    ('BIO 003', 5, '3', 'Structures, Morphology and Characteristics of Microorganisms', 'Morphology and Structures of Microbial Cells, Biochemical Characterization Reproduction, Growth Types and Phases.', 'Structure of bacteria cells- capsule, flagella, pilli and fimbriae, cell wall, plasma membrane, cytoplasm Cell wall of fungal cells, cytoplasm Cultural characteristics of bacterial growth-on solid and liquid media, forms of growth Cultural and cellular characteristics of mould and yeast on solid and liquid media, hyphal and mycelial types Biochemical characterization of bacteria and fungi Viruses and their structures Reproduction and microbial growth phases', 271::int),
    ('BIO 003', 6, NULL, NULL, NULL, 'Practical class Cultivation and identification of bacteria from soil, water and decomposing food', 271::int),
    ('BIO 003', 7, '4', 'Microbial Ecology', 'Microbial Interactions with Animals, Plants and Microbes', 'Predation, Competition, Synergism, Commensalism, Infectious diseases, Immunity, Spoilage of food, Control of microbial activities', 272::int),
    ('BIO 003', 8, '5', 'Microbial Nucleic Acids in Information Storage and Transfer', 'Genetic Materials, Mutation and Mutagenesis', 'Nature of DNA, Nucleosides and nucleotides, Types of RNA, Enzymes in DNA replication, Genetic code, Transcription and translation, Transfer of genetic materials in prokaryotes, Spontaneous mutation, induced mutation, expression of mutation.', 272::int),
    ('BIO 003', 9, '6', 'Microorganisms and their Application in Biotechnology', 'Biotechnological Application of Microorganism in Various Fields', 'Biotechnological use of microorganisms in Food industry, Environment, Pharmaceuticals, Medical and Agricultural fields.', 272::int),
    ('BIO 004', 1, '1', 'Diversity and General Characteristics of Animals', 'What is Zoology? What are Animals? Scope and Areas in Zoology Importance of Zoology', 'Definition, General characteristics of animals, Diversity of lifestyles, habitats, Categories of animals', 272::int),
    ('BIO 004', 2, '2', 'Systematics (Taxonomy) of Animals', 'Classification of Animals, Basis of Animal Classification, Levels of Animal Organization - Phyla of Animals - Tissues and Organs in Animals', 'Unicellular levels of organization- protozoa, Cellular levels of organization- eumetazoa Multicellular levels of organization- metazoan, Classification of invertebrates
- Animals without tissues
- Animals with tissues
- Animals exhibiting bilateral symmetry (bilateria)
- Animals with body cavity (coelomates).
- Segmented animals
- Animals with jointed appendages
- Animals with backbone (vertebrates) Major and minor phyla Types of tissues and organ systems', 273::int),
    ('BIO 004', 3, NULL, NULL, NULL, 'Practical class
- Identification and classification of animal specimens in the different phyla
- Dissection of selected animals- cockroaches, fish, frog, rat, etc.', 273::int),
    ('BIO 004', 4, '3', 'Evolution of Animals', 'History and Origin of Animals, Major Evolutionary Adaptation of Animals', 'Adaptation of animals in water, Adaptation of animals on land, Adaptation of animals in air', 273::int),
    ('BIO 004', 5, '4', 'Invertebrates', 'Phylum Protozoa Phylum Porifera Phylum Cnidaria (Coelenterata) Phylum Platyhelminthes Phylum Nematoda Phylum Annelida Phylum Arthropoda Phylum Mollusca Phylum Echinodermata', 'Taxonomy, characteristics, diversity, lifestyles, morphology and life cycle providing named representative examples in each order Free living flat worms Parasitic flat worms (trematodes and cestodes) of medical and veterinary importance Emphasize on the body plan Why arthropods are successful.', 274::int),
    ('BIO 004', 6, '5', 'Introduction to Chordates', '• Introduction to Chordates and Vertebrates • Hemichordates • Protochordates (Urochordates & Cephalochordates) & • Vertebrates Adaptation of Chordates to Water, Land and Air. Protochordates - Class Chondrichthyes - Class Osteichthyes - ClassAmphibia - ClassReptilia - Class Aves - Class Mammalia', 'Challenges and adaptations to living in the different habitats, History and important adaptations, Diversity, classification, morphology and life cycle, providing, representative examples from the different orders, History and important adaptations, Rise and fall of dominant reptiles, Clearly state the taxonomic features that warrant the grouping into classes.', 274::int),
    ('BIO 004', 7, '6', 'Ecologic and Economic Importance of Animals', 'Ecologic and Economic Importance of Animals Diverse Economic Importance of Animals - Invertebrates', 'Benefits of animals to man, Economic importance of arthropods', 274::int),
    ('BIO 004', 8, NULL, NULL, '- Vertebrates Ecological Importance of Animals', NULL, 275::int),
    ('BIO 004', 9, '7', 'Physiological Processes', 'Nutrition in Animals', 'Types of nutrition in animals, Nutrition in human, Types of dentition in animals, Alimentary system in man, Digestion (diverse enzymes) and absorption', 275::int),
    ('BIO 004', 10, NULL, NULL, NULL, 'Practical class Food test', 275::int),
    ('BIO 004', 11, NULL, NULL, 'Respiration in Animals', 'Characteristics of respiratory surfaces (Skin, Gills, Malphigian Tubules), Structure and Function. Lung as a respiratory organ, Breathing mechanism, Human respiratory structure and function Role of circulatory system in respiration.', 275::int),
    ('BIO 004', 12, NULL, NULL, 'Skeletal System and Muscles', 'Axial and appendicular skeleton, Types of muscular movement, Control of muscle contraction, Joints (types of joints) & Functions of skeleton.', 275::int),
    ('BIO 004', 13, NULL, NULL, 'Reproduction in Animals', 'Mammalian reproductive organs -Spermatogenesis/oogenesis -Courtship/mating and viviparity -Hormonal regulation in male and female systems -Gonadal steroids and their control -The menstrual cycle -Hormone of human pregnancy and birth Structure and function of human female and male reproductive system.', 276::int),
    ('BIO 004', 14, NULL, NULL, 'Excretion in Animals', 'Structure and Function of Excretory Structures in Animals, Morphology of the excretory system in Mammals, Osmoregulation, Structure and function of the nephron – ultrafiltration, selective reabsorption and excretion. Also he effects of weather on excretion.', 276::int),
    ('BIO 004', 15, NULL, NULL, 'Circulatory System in Animals', 'Structure and Functions of Circulatory Structures in Animals. Human circulatory/transport system, Blood as agent of transport,
- Components of blood
- The functions of blood and types of circulation', 276::int),
    ('BIO 004', 16, NULL, NULL, 'Growth and Development', 'Principles of development-stages in embryology.', 276::int),
    ('BIO 004', 17, NULL, NULL, 'Skeletal System and Muscles', 'Axial and appendicular skeleton, Types of muscular movement, Control of muscle contraction, Joints (types of joints) & Functions of skeleton.', 277::int),
    ('BIO 004', 18, NULL, NULL, 'Growth and Development', 'Principles of development-stages in embryology.', 277::int),
    ('BIO 004', 19, '8', 'Transport of Substances across Membranes', 'Diffusion Osmosis Plasmolysis Flaccidity Haemolysis Crenation & Turgidity', 'Osmotic balance, Selective transport of substances across membranes, Osmotic pressure, Turgor pressure & Active transport', 277::int),
    ('BIO 004', 20, NULL, NULL, NULL, 'Practical class Experiment demonstrating diffusion, osmosis and plasmolysis', 277::int),
    ('BIO 004', 21, '9', 'Nervous System', 'Coordination and control', 'Nerve cells (Neuron and reflex) Structure of neuron Reflex arc Central nervous system Peripheral nervous system Sympathetic and parasympathetic nervous system', 277::int),
    ('BIO 004', 22, '10', 'Sense Organ', 'Structures and functions of sense organs Chemoreception, Mechanoreception and Photoreception', 'Structures and functions of Human ears, eyes, nose, skin and tongues', 277::int),
    ('BIO 004', 23, '11', 'Endocrine System', 'Mechanism of Hormonal Action', 'Types of hormones, Control of Hormonal actions, Secreting glands, Functions of hormones', 278::int),
    ('CHM 001', 1, '1', 'Measurement', 'Units of Measurement', 'Basic S.I. Units, derived units, conversion of units, significant figures.', 281::int),
    ('CHM 001', 2, NULL, NULL, 'Data analysis', 'Precision and accuracy, errors (systematic and random errors). Error calculations (Standard deviation, relative error, absolute error, and percentage relative error).', 281::int),
    ('CHM 001', 3, '2', 'Mole concept', 'Atomic masses', 'Isotopy. Use of mass spectrometry in the determination of Relative Atomic Mass. Calculation of relative abundances and isotopic masses.', 281::int),
    ('CHM 001', 4, NULL, NULL, 'The mole', 'Definitions of the mole based on 12C and Avogadro’s constant. Calculation based on Avogadro’s constant. Relative Molecular Mass.', 282::int),
    ('CHM 001', 5, NULL, NULL, 'Empirical and molecular formula', 'Definition and calculations of Empirical and Molecular formulae from percentage composition by mass and combustion data.', 282::int),
    ('CHM 001', 6, NULL, NULL, 'Stoichiometry', 'Definition and calculations of molarity, molality, mole fraction, and mass concentration.', 282::int),
    ('CHM 001', 7, NULL, NULL, 'Standard solutions', 'Primary and secondary standard. Preparation of standard solutions, serial dilution.', 282::int),
    ('CHM 001', 8, '3', 'Atomic structure', 'Discovery of sub-atomic particles', 'Shortcomings of Dalton’s atomic theory. Various experiments that led to the discovery of neutrons, protons, electrons, and nuclei [Cathode ray, Millikan''s cathode ray, Rutherford and Chadwick experiment].', 282::int),
    ('CHM 001', 9, NULL, NULL, 'Planck’s theory', 'Black body radiation, photoelectric effect, quantisation of energy.', 282::int),
    ('CHM 001', 10, NULL, NULL, 'Bohr’s theory', 'Bohr’s assumption, atomic spectra of hydrogen, and determination of spectral lines, determination of ionisation energy from line spectra (when n=∞).', 282::int),
    ('CHM 001', 11, NULL, NULL, 'Wave theory of the atom', 'Particle wave duality. Atomic orbitals, quantum numbers (n, l, m, and s). Including relation to energy level, degeneracy, and orientation of atomic orbitals. Shapes of s, p, and d orbitals only.', 282::int),
    ('CHM 001', 12, NULL, NULL, 'Electron configuration', 'Aufbau principle, Pauli’s exclusion principle, Hund’s rule.', 283::int),
    ('CHM 001', 13, '4', 'Periodic Table', 'Modern Periodic Table', 'Development of the modern periodic table, building up periods, identifying blocks and groups of elements, and the periodic law.', 283::int),
    ('CHM 001', 14, NULL, NULL, 'Atomic Properties', 'Trends of atomic size, ionisation potential, electron affinity, electronegativity, and ionic radii, isoelectronic species.', 283::int),
    ('CHM 001', 15, '5', 'Types of chemical reactions', 'Neutralisation', 'Definition and identification of neutralization reactions. Identify the characteristics of acids, bases, and salts, and solve problems based on their quantitative relationship: Strong acid-weak base; weak acid-strong base, etc.', 283::int),
    ('CHM 001', 16, NULL, NULL, 'Precipitation', 'Predicting solubility. Identification of precipitation reactions.', 283::int),
    ('CHM 001', 17, NULL, NULL, 'Oxidation and Reduction', 'Various definitions of oxidation and reduction reactions. Calculation of oxidation numbers, balancing of redox reactions using oxidation state and half-reaction method (both in acidic and basic media). Disproportionation reaction.', 283::int),
    ('CHM 001', 18, NULL, NULL, 'Displacements', 'Single and double displacement reactions, metathesis.', 283::int),
    ('CHM 001', 19, '6', 'Chemical Bonding', 'Electrovalent/Ionic Bonding', 'Describe ionic bonding using some ionic compounds, e.g., NaCl, energy considerations of ionic bonding, definition of lattice energy (no derivation), properties of ionic compounds.', 284::int),
    ('CHM 001', 20, NULL, NULL, 'Covalent bonding', 'Describe covalent bonding using some covalent compounds (e.g., CO ,),coordinate/dative covalent 2 bonding (e.g., in ammonium ion (NH +), Al Cl molecule), bond 4 2 6 energy, bond length, and bond polarity (Fajan’s rule). Properties of covalent compounds, hybridisation concept (sp, sp2, sp3, sp2d, sp3d, sp3d2).', 284::int),
    ('CHM 001', 21, NULL, NULL, 'Molecular geometry', 'Shapes of simple molecules (e.g., H O, NH CH PCl , SF , CO ) 2 3, 4, 5 6 2 using the valence shell electron-pair repulsion theory.', 284::int),
    ('CHM 001', 22, NULL, NULL, 'Metallic bonding', 'Describe metallic bonding in terms of a lattice of positive ions surrounded by delocalised electrons.', 284::int),
    ('CHM 001', 23, NULL, NULL, 'Intermolecular', 'Van der Waals forces, permanent and induced dipoles, and hydrogen bonding. The effect of intermolecular forces on the physical properties of substances (e.g. unusual high boiling, miscibility of water with ethanol, nylon, polyester).', 284::int),
    ('CHM 002', 1, '1', 'Kinetic Theory of Matter', 'Nature of Matter', 'Definition of Matter, State of Matter, Properties of State of Matter', 285::int),
    ('CHM 002', 2, NULL, NULL, 'Phase and phase diagrams', 'Interconversion between the three states of matter. Interpretation of', 285::int),
    ('CHM 002', 3, NULL, NULL, NULL, 'the phase diagram for one component system.', 286::int),
    ('CHM 002', 4, NULL, NULL, 'Kinetic Molecular Theory of Gases', 'Gas Laws and calculations involving Boyle’s, Charles’, Avogadro’s law, Dalton’s, Graham’s laws, and Gay Lussac’s law.', 286::int),
    ('CHM 002', 5, NULL, NULL, 'Ideal and Real Gases', 'Kinetic theory of gases (assumptions only). Calculations involving general and Ideal gas equations. Gas densities and molar mass. Boltzmann’s distribution of molecular speed, Mean, Root-Mean square, and most probable Velocities. Real gases deviation from ideal gas behaviour, Van der Waals’ equation.', 286::int),
    ('CHM 002', 6, '2', 'Solutions', 'Types of Solutions', 'Definition of solution, Types including saturated, unsaturated, super saturated.', 286::int),
    ('CHM 002', 7, NULL, NULL, 'Ideal and Non-Ideal Solutions', 'Definition of ideal solutions, Raoult’s Law, and its Deviations.', 286::int),
    ('CHM 002', 8, NULL, NULL, 'Colligative Properties', 'Lowering of vapour pressure, depression of freezing point, elevation of boiling point, and osmotic pressure. Determination of molar masses using Colligative properties. (The derivation is not required.)', 286::int),
    ('CHM 002', 9, '3', 'Thermochemistry', 'Enthalpy Change', 'Exothermic and endothermic changes. Definition of enthalpy changes for processes (combustion, neutralization, hydration, formation, solution, and atomization) under standard conditions.', 286::int),
    ('CHM 002', 10, NULL, NULL, 'Hess’s Law', 'State Hess’s law calculation based on Hess’s law and the construction of energy cycles based on Hess’s law. Born-Haber cycle for and carry out calculation of lattice energy. s based on Hess’ law Use of bond energy to calculate energy changes.', 287::int),
    ('CHM 002', 11, '4', 'Thermodynamics', 'Laws of thermodynamics', 'Definition of laws: zeroth, first, second. Calculations in the first law of thermodynamics: Internal energy, heat change, and work done (no derivations). Concept of isothermal and adiabatic processes.', 287::int),
    ('CHM 002', 12, NULL, NULL, 'Entropy and Gibbs’ free energy', 'Definition of entropy changes. Calculations involving entropy change and Gibbs’ free energy change for reactions using ∆G = ∆H –T∆S. Predicting the spontaneity of reactions', 287::int),
    ('CHM 002', 13, '5', 'Electrochemistry', 'Electrolysis', 'Ohm’s law, Faraday’s first and second laws of electrolysis, and calculations based on them. Identify the substances liberated during electrolysis based on the state of electrolyte, position in the electrochemical series, concentration of electrolyte, and nature of electrodes. Industrial uses of electrolysis.', 287::int),
    ('CHM 002', 14, NULL, NULL, 'Conductance of electrolyte solution', 'Definition and Types of conductance; specific, equivalent and Molar Conductance', 287::int),
    ('CHM 002', 15, NULL, NULL, 'Electrochemical Cells', 'Definitions of electrode potential, standard electrode potential, and cell potential. Calculations of the e.m.f of a cell. Application of the Nernst equation. Use of cell potential to predict the feasibility of reactions.', 288::int),
    ('CHM 002', 16, NULL, NULL, 'Fuel Cells and Batteries', 'H /O fuel cell, rechargeable 2 2 batteries.', 288::int),
    ('CHM 002', 17, '6', 'Chemical Kinetics', 'Rate Equations', 'Define and explain rate of reaction, order, molecularity, and rate determining step, and reaction mechanism. Factors affecting the rate of reaction, rate constants. Determination of orders of reaction (0, 1, and 2), half-life, and rate constants from experimental data. Calculations of the order of reaction from experimental data.', 288::int),
    ('CHM 002', 18, NULL, NULL, 'Activation energy', 'Simple collision theory. Definition of activation energy. Arrhenius equation.', 288::int),
    ('CHM 002', 19, NULL, NULL, 'Catalysis', 'Homogeneous and Heterogeneous Catalysis. Identify homogenous and heterogeneous catalysts from equations.', 288::int),
    ('CHM 002', 20, '7', 'Equilibrium State', 'Mass Action', 'Equilibrium changes, reaction quotient (Q), equilibrium expressions (homogeneous and heterogeneous equilibria). Calculations of equilibrium constants in terms of concentration (K ) and partial pressure (K ). c p Relationship between K and K . c p Predicting spontaneity using the equilibrium constant', 288::int),
    ('CHM 002', 21, NULL, NULL, 'Le-Chatelier’s Principle', 'Application of Le-Chatelier’s principle to deduce the effects of', 288::int),
    ('CHM 002', 22, NULL, NULL, NULL, 'changes in temperature, pressure, and concentration on a system at equilibrium.', 289::int),
    ('CHM 002', 23, NULL, NULL, 'Acid-Base Equilibria', 'Arrhenius, Bronsted-Lowry, and Lewis concepts of acid and base. Auto-ionisation of water. Acid strengths, pH of acids and bases (strong and weak). Indicator theory. Buffer solution: Definition, types, pH (Henderson equation).', 289::int),
    ('CHM 002', 24, NULL, NULL, 'Ionic Equilibra in Aqueous System', 'Solubility product, common ion effect. Selective precipitation of ions. Salt hydrolysis.', 289::int),
    ('CHM 002', 25, '8', 'Nuclear Chemistry', 'Radioactivity', 'Types of radiation, nuclear stability, types of radioactivity. History of Radioactivity. Types of radiation. Radioactive disintegration. Balancing of nuclear equations, half-life, and radioactive carbon dating. Detectors and applications of radioactivity.', 289::int),
    ('CHM 002', 26, NULL, NULL, 'Energy changes in a nuclear reaction', 'Mass defect, energy changes', 289::int),
    ('CHM 003', 1, '1', 'Periodicity', 'General Trends in Properties', 'General trends in physical and chemical properties of period III elements and their compounds (chlorides, oxides, and hydrides). Diagonal relationship between elements in periods II and III. Anomalous behaviour of period II elements.', 290::int),
    ('CHM 003', 2, NULL, NULL, 'Solid structure of the elements', 'Definition and types, e.g., face centered, body centered and hexagonal closed packing. Structure-properties relationship.', 290::int),
    ('CHM 003', 3, '2', 'Chemistry of Hydrogen', 'Hydrogen', 'Occurrence, isotopes, preparation, physical and chemical properties, and their hydrides.', 290::int),
    ('CHM 003', 4, '3', 's-block elements', 'Group 1', 'Physical and chemical properties, extraction of group 1 metals, e.g., Sodium. Trends in properties of their compounds (chlorides, oxides, hydrides, carbonates, hydroxides,', 290::int),
    ('CHM 003', 5, NULL, NULL, NULL, 'nitrates, and sulphates). Uses of group 1 metals.', 291::int),
    ('CHM 003', 6, NULL, NULL, 'Group 2', 'Physical and chemical properties, extraction of group 2 metals, e.g., Calcium. Trends in properties of their compounds (chlorides, oxides, hydrides, carbonates, hydroxides, nitrates, and sulphates). Uses of group 2 metals.', 291::int),
    ('CHM 003', 7, '4', 'p-block elements', 'Boron and Aluminium', 'Physical and Chemical properties, Anomalous behavior of Boron, formation of Boranes and Boron hydrides, Amphoteric nature of Aluminum (Reaction with Acids and Bases), Inert pair effect (Stability of +3 and +1 oxidation states), Aluminum alloys and their uses, Uses of group 13 elements.', 291::int),
    ('CHM 003', 8, NULL, NULL, 'Group 14', 'Occurrence, allotropic forms of carbon (diamond, amorphous carbon, and fullerene) and tin. Trends in physical and chemical properties of the elements, oxides, hydrides, and halides. Uses of group 14 elements.', 291::int),
    ('CHM 003', 9, NULL, NULL, 'Group 15', 'Occurrence, allotropic forms. Trends in physical and chemical properties of the elements, oxides, hydrides, and halides. Uses of group 15 elements.', 291::int),
    ('CHM 003', 10, NULL, NULL, 'Group 16', 'Occurrence, allotropic forms. Types of oxides. Trends in physical and chemical properties of the elements, oxides, hydrides, and halides. Uses of group 16 elements.', 291::int),
    ('CHM 003', 11, NULL, NULL, 'Group 17', 'Occurrence, physical and chemical properties, hydrogen halides, metal', 291::int),
    ('CHM 003', 12, NULL, NULL, NULL, 'halides, and inter-halogen compounds. Uses of group 17 elements.', 292::int),
    ('CHM 003', 13, '5', 'Chemistry of the Environment', 'Environmental impact', 'Greenhouse effect. Environmental impacts of greenhouse gases, NOx, SOx. Acid rain, ozone layer depletion, and global warming.', 292::int),
    ('CHM 003', 14, '6', 'd-block elements', 'First Row Transition Elements', 'Definition of transition elements, electronic configuration. Periodic trends in atomic radii, ionization potential, and variable oxidation states. Properties of transition elements.', 292::int),
    ('CHM 003', 15, NULL, NULL, 'Introduction to Coordination Chemistry', 'Definition of metal complex and ligands, types of ligands. Bonding in metal complexes (chain theory and its limitations, Werner’s theory). Valence bond theory (to explain the properties of coordination compounds). Study of the structure and magnetic properties of octahedral and tetrahedral complexes. Nomenclature of coordination compounds.', 292::int),
    ('CHM 003', 16, '7', 'Nanochemistry', 'Introduction to dimensions of nanomaterials', 'Definition of nanomaterials and nanotechnology. Classification of nanostructures. Sources of nanomaterials and examples (nanotubes, graphene, quantum dots, etc.).', 292::int),
    ('CHM 004', 1, '1', 'Development and Importance of Organic Chemistry', 'Sources of organic compounds, the unique nature of carbon', 'Tetravalency, Catenation, multiple hybridization states and geometries, stable multiple bonds. Mention application in the pharmaceutical, petrochemical, and fuel industries, etc.', 293::int),
    ('CHM 004', 2, '2', 'Separation and Purification Techniques', 'Separation Techniques', 'Distillation, liquid extraction, sublimation, recrystallization, and melting point. Chromatography (TLC and Paper chromatography)', 293::int),
    ('CHM 004', 3, NULL, NULL, 'Structural determination of organic compounds using qualitative and quantitative analysis.', 'Sodium fusion test, functional groups. Determination of empirical formula and molecular formula.', 293::int),
    ('CHM 004', 4, '3', 'Structure and Bonding in', 'Hybridization', 'Tetravalency and hybridization of carbon. Sigma and pi bond formation.', 293::int),
    ('CHM 004', 5, NULL, 'Organic Compounds', 'Classes and Nomenclature of Organic Compounds', 'Homologous series, Functional groups, Naming of organic compounds (IUPAC): alkanes, alkenes, alkynes, aldehydes, ketones, alcohols, alkyl halides, arenes, carboxylic acids (and derivatives), amines, and amides.', 294::int),
    ('CHM 004', 6, '4', 'Organic Reactions', 'Covalent Bond Cleavage', 'Homolytic and heterolytic fission, free radicals, Nucleophiles and electrophiles.', 294::int),
    ('CHM 004', 7, NULL, NULL, 'Mechanism of Reactions', 'Addition, Substitution, and Elimination reactions. Radical reaction. Differences between S 1 N and S 2 S 1 and S 2. N E E', 294::int),
    ('CHM 004', 8, NULL, NULL, 'Electronic Concepts in Organic Chemistry', 'Inductive, steric, mesomeric, and electromeric effects.', 294::int),
    ('CHM 004', 9, '5', 'Stereochemistry', 'Isomerism in Organic Compounds', 'Constitutional; chain, position, metamerism, and functional group isomerism. Tautomerism. Stereoisomerism; geometrical (Cis/ Trans, E/Z) and optical isomerism (chirality and optical activity).', 294::int),
    ('CHM 004', 10, '6', 'Organic Compounds', 'Alkanes, Alkenes, and Alkynes', 'Nomenclature, structure, synthesis, properties, and reactions (for alkene include Markovnikov and Saytzeff’s rules).', 294::int),
    ('CHM 004', 11, NULL, NULL, 'Alcohols', 'Nomenclature, classes, and structure. Synthesis, properties, and reactions. Distinguishing tests for alcohols (Lucas and Jones reagents).', 294::int),
    ('CHM 004', 12, NULL, NULL, 'Alkyl halides', 'Nomenclature, structure, synthesis, properties, and reactions.', 294::int),
    ('CHM 004', 13, NULL, NULL, 'Carbonyl Compounds', 'Nomenclature, structure, synthesis, properties, and reactions (including reduction, reaction with HCN, NaCN, reaction with aqueous I ). 2 Tests for aldehydes and ketones.', 295::int),
    ('CHM 004', 14, NULL, NULL, 'Carboxylic acids and their derivatives (treat each separately).', 'Nomenclature, properties. Preparation and reactions.', 295::int),
    ('CHM 004', 15, NULL, NULL, 'Amines and Nitriles', 'Nomenclature and classification of amines and nitriles. Preparation of primary alkylamines. Basicity of amines in terms of their structure. Reactions of amines (formation of diazonium salt)', 295::int),
    ('CHM 004', 16, NULL, NULL, 'Ethers', 'Nomenclature, properties. Preparation and reactions.', 295::int),
    ('CHM 004', 17, NULL, NULL, 'Aromatic compounds', 'Kekule structures. Aromaticity. Reactions of benzene (Nitration, sulphonation, halogenation, Friedel-Crafts). Nomenclature of benzene derivatives (mono and di-substituted). Effects of substituents on the reaction of benzene (o, m, p-directors).', 295::int),
    ('CHM 004', 18, '7', 'Macromolecules', 'Carbohydrates (Open chain structures only)', 'Classes of carbohydrates: sugar, starch, and cellulose. Simple tests', 295::int),
    ('CHM 004', 19, NULL, NULL, 'Proteins', 'Amino acids. Reactions of amino acids (formation of peptide bonds, zwitterions). Classification of peptides. Types of proteins.', 295::int),
    ('CHM 004', 20, NULL, NULL, 'Polymers', 'Types of polymerization reactions and their differences. Simple structures of polymers. Uses of common polymers. Differences between thermosets and thermoplastics.', 296::int),
    ('CHM 004', 21, '8', 'Petroleum Industry', 'Petrochemicals', 'Constituents of crude oil, refining, and cracking. Chemicals derived from crude oil.', 296::int),
    ('MAT 001', 1, '1', 'Set Theory', 'Set Theory', 'Operations of sets (subset, union, intersection, complements, Cartesian Product), Algebra of sets (commutative, associative, distributive, idempotent laws), Venn diagram and its applications to word problems.', 300::int),
    ('MAT 001', 2, '2', 'Real Numbers', 'Operations with Real Numbers', 'Integers, rational and irrational number, mathematical induction, sequence and series (to include Arithmetic, Geometric and Harmonic Progressions), Sum to infinity of Geometric Progression and its convergence, binary operations (simple illustrations of uniqueness of identity and inverse elements)', 300::int),
    ('MAT 001', 3, '3', 'Algebra', 'Mappings', 'Compositions of mapping, domain, range, one-to-one, onto mapping, inverse functions and composite functions.', 301::int),
    ('MAT 001', 4, NULL, NULL, 'Simultaneous Equation', 'Solutions of equations in one and two variable (Elimination, Substitution and Graphical methods)', 301::int),
    ('MAT 001', 5, NULL, NULL, 'Theory of Quadratic Equations', 'The roots of quadratic equations (completing the square, using the discriminant to determine the nature of roots), theory of quadratic equations and functions, relationship between the roots and coefficients of quadratic equations.', 301::int),
    ('MAT 001', 6, NULL, NULL, 'Polynomials', 'Polynomial as an equation up to degree 3, the Factor theorem and the Remainder theorem. Partial fractions.', 301::int),
    ('MAT 001', 7, NULL, NULL, 'Binomial Theorem', 'Expansions, Pascal triangles, Binomial theorem and linear approximations.', 301::int),
    ('MAT 001', 8, NULL, NULL, 'Logarithms', 'The relationship between logarithm and indices, change of base, and the natural logarithm.', 301::int),
    ('MAT 001', 9, NULL, NULL, 'Matrices', 'Algebra of matrices of not more than 3 x 3, Properties of matrices, Determinant, Singular and inverse of matrices. Applications to system of linear equations up to three unknowns (Inverse and Cramer’s Rule methods).', 301::int),
    ('MAT 001', 10, NULL, NULL, 'Inequalities', 'Linear and quadratic inequalities in one variable, Simultaneous (one linear, one quadratic) using graphical solution. Absolute value and intervals.', 301::int),
    ('MAT 001', 11, '4', 'Trigonometry', 'Trigonometric Functions', 'Radians and Degrees conversion, trigonometric functions of angles of any magnitude and simple trigonometric equations, graphs of trigonometric functions (sine, cosine, and tangent). Inverse of trigonometric functions. Use of trigonometric identities.', 302::int),
    ('MAT 001', 12, '5', 'Complex Numbers', 'Complex Numbers', 'Basic complex numbers, Algebra of complex numbers, the Argand diagram, complex numbers in polar form, De-Moivre’s theorem with proof, nth root of unity and loci problems.', 302::int),
    ('MAT 002', 1, '1', 'Functions', 'Functions', 'Functions of a real variable, types of functions (elementary: algebraic, exponential, logarithmic, trigonometric; absolute value, etc), inverse of elementary functions, and graphs of functions', 302::int),
    ('MAT 002', 2, NULL, NULL, 'Limits and Continuity', 'Definition of limits of function, properties of limits of functions, evaluation of limits of functions. L’Hospital’s rule. Notion of continuity.', 303::int),
    ('MAT 002', 3, '2', 'Differential Calculus', 'Differentiation', 'Gradients, differentiation from the first principle, differentiation of elementary functions. Techniques of differentiation: chain rule, product rule, and quotient rule. Derivatives of implicit and parametric functions. Higher order derivatives. Partial Differentiation not more than two variables', 303::int),
    ('MAT 002', 4, NULL, NULL, 'Applications of Differentiation', 'Tangent and normal to a curve, maximum and minimum, rate of change, asymptotes and curve sketching. Maclaurin and Taylor series. Rectilinear motion.', 303::int),
    ('MAT 002', 5, '3', 'Integral Calculus', 'Integration', 'Standard integrals, integration as inverse of differentiation, definite integrals, techniques of integration (substitution method, inverse trigonometric function, integration by parts, use of partial fraction and reduction formula).', 303::int),
    ('MAT 002', 6, NULL, NULL, 'Applications of Integration', 'Areas, volumes, numerical methods of integration:
Trapezoidal and Simpson rules.', 303::int),
    ('MAT 002', 7, '4', 'Ordinary Differential Equations', 'First order Ordinary Differential Equations', 'Introduction to ordinary Differential equation:
identification, classification (types, order, linear non-linear, Initial Value Problem (IVP) and Boundary Value Problems (BVP)). Formulation of simple first order differential equations, solution when the variables are separable, homogenous and is linear (Bernoulli equation) and use of an initial condition.', 303::int),
    ('MAT 002', 8, NULL, NULL, 'Applications', 'Geometric, exponential growth and decay problems.', 303::int),
    ('MAT 003', 1, '1', 'Introduction to Statistics', 'Description of Data set', 'Definition of Statistics, types of data, sources of data, population and sample, graphical representation of data (frequency table, histogram, bar chart, pie chart, stem-and-leaf display, box plot, frequency distribution, frequency polygon and Ogive).', 304::int),
    ('MAT 003', 2, '2', 'Different Measures', 'Measures of location and dispersion', 'Measure of central tendency for grouped and ungrouped data (mean, median and mode), Quartiles (1st, 2nd and 3rd) and percentiles, Measure of dispersion for grouped and ungrouped data (mean deviation, standard deviation and variance), interquartile range, coefficient of variation, Skewness and Kurtosis using central tendency and dispersion measure, Rate, ratio and index of numbers.', 304::int),
    ('MAT 003', 3, '3', 'Combinatorics', 'Mathematics of Counting and introduction to probability', 'Permutation and Combination, fundamental principles of probability theory (union of events, mutually exclusive events, independent events and conditional events), simple practical probability problems using venn diagram.', 305::int),
    ('MAT 003', 4, '4', 'Random Variables', 'Probability', 'Discrete and continuous random variables, Probability Density Function (Normal distribution) and Probability Distribution Functions (Bernoulli, Binomial, Geometric and Poisson)', 305::int),
    ('MAT 003', 5, NULL, NULL, 'Discrete Random Variables', 'Find the mean and variance from a probability distribution table and the linear properties of expectation and variance.', 305::int),
    ('MAT 003', 6, NULL, NULL, 'Discrete Probability Density Function, Expectation and Variance', 'Expectation and variance of the following distributions: Bernoulli, Binomial, Geometric and Poisson. Use of the Binomial and Poisson tables.', 305::int),
    ('MAT 003', 7, '5', 'Normal Random Variables', 'Normal distribution', 'Use of Standard Normal table, Normal distribution as a model for data and its applications to real life problems.', 305::int),
    ('MAT 003', 8, NULL, NULL, 'Significance Testing', 'Test of hypothesis, errors in hypothesis testing, significance tests using Normal distribution and Student t-distribution, Chi-square test (goodness of fit test and contingency table), one sample mean test, difference of mean, one sample proportion test.', 305::int),
    ('MAT 003', 9, '6', 'Correlation and Regression', 'Correlation and Simple Regression', 'Types of correlation, simple correlation, correlation coefficients (Pearson product-moment and Spearman’s rank), simple real-life problems. simple linear regression.', 305::int),
    ('MAT 003', 10, '7', 'Basic Sampling Techniques', 'Types of Sampling Techniques', 'Simple sampling techniques, finite and infinite sampling sizes.', 306::int),
    ('MAT 004A', 1, NULL, 'Coordinate Geometry', 'Straight Line', 'Length, gradient and mid-point of straight line. Equation of straight line (coordinate of two points and one point, and their gradients).', 306::int),
    ('MAT 004A', 2, NULL, NULL, NULL, 'Association between the gradients of parallel and perpendicular lines.', 307::int),
    ('MAT 004A', 3, NULL, NULL, 'Conic Sections', 'Circles, parabola, ellipse, hyperbola and their properties (e.g., tangents and normal).', 307::int),
    ('MAT 004A', 4, '1', 'Vectors', 'Vectors', 'Scalar and vector quantities, types of vectors, representation and naming of vectors.', 307::int),
    ('MAT 004A', 5, NULL, NULL, 'Algebra of Vectors', 'Addition, subtraction and scalar multiplication, commutativity and associativity, linear dependence and co-linearity of vectors, perpendicularity of vectors and the angles between two vectors.', 307::int),
    ('MAT 004A', 6, NULL, NULL, 'Vector Equations', 'Vector equation of lines and planes, application to geometry, vectors in three dimensions, and the rectangular unit vectors i, j, and k. Representation of vectors in terms of rectangular coordinates, scalar and vector functions.', 307::int),
    ('MAT 004A', 7, NULL, NULL, 'Vector Functions', 'Differentiation of vector functions, integration of vector functions (one integral and differential operators of at most order 3).', 307::int),
    ('MAT 004A', 8, '2', 'Kinematics of Motion in a Straight Line', 'Motion in a straight line', 'Unit vectors, position vectors, speed, velocity, acceleration and displacement in simple cases. Area under a velocity-time graph representing displacement, and gradient of velocity-time graph representing acceleration. Gradient of a displacement-time graph representing velocity.', 307::int),
    ('MAT 004A', 9, NULL, NULL, 'Rectilinear motion', 'Rectilinear motion with uniform acceleration, motion under gravity, and graphical method.', 307::int),
    ('MAT 004A', 10, NULL, NULL, 'Motion in a plane', 'Rectangular components of velocity and acceleration, resultant velocity, relative velocity and relative path.', 307::int),
    ('MAT 004A', 11, '3', 'Newtonian Mechanics', 'Newtonian Mechanics', 'Energy, work and power (simple cases).', 308::int),
    ('MAT 004A', 12, NULL, NULL, 'Force and Motion', 'Force and motion, momentum, Newton’s laws of motion, different kinds of forces (gravitational reactions, tension, and thrust), motion of connected particles and motion of a particle on an inclined plane.', 308::int),
    ('MAT 004A', 13, '4', 'Forces and Equilibrium', 'Forces and Equilibrium', 'Forces acting at various points of a rigid body, parallel forces, couple, moment and application of vectors in statics (simple cases).', 308::int),
    ('MAT 004B', 1, '1', 'Mathematics of Finance', 'Interest Application', 'Simple interest, accumulated value of simple interest loan, compound interest, continuous compound interest, time value concept (payback period, net present value, internal rate of return), future of a single sum.', 308::int),
    ('MAT 004B', 2, NULL, NULL, 'Annuities and Perpetuity', 'Annuity: Ordinary annuity, deferred annuity, present value of an annuity due. Perpetuity:
present value of a level perpetuity, present value of a growing perpetuity.', 309::int),
    ('MAT 004B', 3, NULL, NULL, 'Sinking fund and loan amortization', 'Computation of due date/terminal value, amount and future value, loan amortization schedule.', 309::int),
    ('MAT 004B', 4, NULL, NULL, 'Inventory and turnover', 'Techniques of inventory control (average cost, First in first out, Last in first out), computing inventory at the lower of cost (market value), estimating inventory value, computing inventory turnover.', 309::int),
    ('MAT 004B', 5, '2', 'Application of Differential Calculus to Business', 'Marginal Concept', 'Marginal productivity, marginal profit, marginal cost and average cost, marginal revenue, marginal demand, price and income elasticity of demand, cross price elasticity.', 309::int),
    ('MAT 004B', 6, '3', 'Application of Integral Calculus to Business', 'Production and Cost Functions', 'Total cost, total revenue, average cost, average revenue, breakeven point.', 309::int),
    ('MAT 004B', 7, NULL, NULL, 'Consumer Surplus and Producer Surplus', 'Demand function, supply function, equilibrium price and quantity, marginal propensity to consume and save, calculation of consumer surplus and producer surplus.', 309::int),
    ('MAT 004B', 8, NULL, NULL, 'Applications', 'exponential growth and decay problems in business.', 309::int),
    ('MAT 004B', 9, '4', 'Optimization', 'Linear Programming', 'Graphical representation of simple linear programming.', 309::int),
    ('PHY 001', 1, '1', 'Physical quantities and units', 'Space and time: coordinate systems and polar coordinates. Definition of Units, Unit Conversion and Measurements, Methods of Measuring Length, Mass and Time. Basic and Derived Units, Dimensional Analysis.', 'Definitions to include length, mass and time. Dimensional Analysis to involve length, mass and time only. Students should be made to explain:
i. the importance of dimensional analysis; and ii. the difference between weight and mass. Emphasis should also be placed on:
i. Error analysis and significant figures; and ii. Graphical analysis. Suggested experiment/activity:
i. Measurement of length, mass and time using relevant measuring instruments.', 314::int),
    ('PHY 001', 2, '2', 'Vectors', 'Addition and Subtraction of Vectors, Resolution of Vectors. Vector Multiplication, Vectors in Cartesian Coordinate System.', 'Scalar and vector quantities, and vector representation are pre-requisites.', 314::int),
    ('PHY 001', 3, '3', 'Kinematics', 'Types of Motion', 'Translational, random, oscillatory, and rotational.', 314::int),
    ('PHY 001', 4, NULL, NULL, 'Linear Motion', 'Distance, displacement, uniform speed, uniform velocity, uniform acceleration', 315::int),
    ('PHY 001', 5, NULL, NULL, 'Graphs of kinematic equations. Average and instantaneous speed, velocity and acceleration. Motion in two and three dimensions. Relative motion in one and two dimensions, Free Fall, Projectile Motion.', 'Suggested experiment/ activity:
i. Measurement of velocity, ii. Measurement of acceleration. iii. Computer simulation of a free-falling body', 315::int),
    ('PHY 001', 6, '4', 'Dynamics', 'Newton’s Laws of Motion, types of Force, Frictional force, Equilibrium of Forces, Motion in inclined planes, Centre of Mass and Centre of Gravity, Moment of a Force, Linear Momentum and its Conservation Laws, Elastic and Inelastic Collisions. Collision in two Dimensions.', 'Students should be made to understand:
i. Equilibrium of parallel forces ii. Equilibrium of forces acting at a point. Suggested experiment/activity:
i. Investigation on the proportionality of acceleration and force. ii. Investigation of the laws of equilibrium for a set of coplanar forces. iii. Investigation of contact forces – static and dynamic friction. iv. Verification of the principle of conservation of momentum.', 315::int),
    ('PHY 001', 7, '5', 'The Gravitational Field', 'Newton’s Universal Law of Gravitation, Field Strength, G and its Measurement, Gravitational Potential, Kepler’s Laws of Planetary', 'Students should note these points:', 315::int),
    ('PHY 001', 8, NULL, NULL, 'Motion, Satellite Motion and Escape Velocity.', 'i. The relationship between Gravitation constant G and the field strength g. ii. Variation of field strength g with altitude. iii. Application to parking orbits.', 316::int),
    ('PHY 001', 9, '6', 'Work, Energy and Power', 'Work, Energy: Sources, Types, Conversion and Conservation, Principle of Conservation of Mechanical Energy, Power.', 'Students should be able to:
i. differentiate between Renewable and non-renewable sources with examples. ii. convert units of power to include kilowatt-hour and horse-power.', 316::int),
    ('PHY 001', 10, '7', 'Circular and oscillatory motions', 'Angular Displacement, Angular Velocity, Angular Acceleration Moment of inertia and Torque, Angular Momentum, Centripetal Acceleration, Centripetal Force, Rotational Kinetic Energy, Work Done in Rotation, Conservation of Angular Momentum. Simple Harmonic Motion, Energy in Simple Harmonic Motion, Damped and Forced Oscillations, Resonance and transients. Coupled SHM, Q values and power response curve.', 'Students should be able to:
i. differentiate between centripetal and centrifugal acceleration. ii. differentiate between centripetal and centrifugal forces. Suggested experiment/activity:
i. Investigation of the relationship between period and length of simple pendulum and hence calculations of acceleration due to gravity (g). ii. Rigid Body and Torsional Oscillation – Moment of Inertia.', 316::int),
    ('PHY 001', 11, '8', 'Elasticity', 'Hooke’s Law, Elastic Limit, Elastic and Plastic Deformations, Ductile and Brittle Substances, Stress, Strain, Elastic and Plastic Behaviour, Young’s Modulus, Energy Stored, Energy per', 'Suggested experiment/activity:
i. Elasticity of materials – Hooke’s law experiments.', 316::int),
    ('PHY 001', 12, NULL, NULL, 'Unit Volume, Shear Modulus, Bulk Modulus.', NULL, 317::int),
    ('PHY 001', 13, '9', 'Hydrostatics', 'Matter (solid, liquid and gases), Density, Pressure in Fluids, Change of Phases, Archimedes’ Principle, Principle of Floatation, Stokes’ Law, Terminal velocity.', 'Suggested experiment/activity:
i. Measurement of density, relative density, pressure and terminal velocity.', 317::int),
    ('PHY 001', 14, '10', 'Hydrodynamics', 'Molecular Properties of Fluids, Turbulent and Laminar flow, Viscosity, Surface Tension, Adhesion, Cohesion, Capillarity, Drops and Bubbles, Bernoulli’s Principle and Pitot-static Tube Principle, Pascal Principle, Reynold’s Number, Poiseuille’s Equation.', 'Students should be able to:
i. differentiate between laminar and turbulent flow ii. explain forces in fluids – surface tension and capillarity iii. apply the continuity equation. Suggested experiment/activity:
i. Determination of viscosity of a viscous fluid.', 317::int),
    ('PHY 002', 1, '1', 'Temperature and Thermometry', 'Concept of Heat and Temperature, Thermal Equilibrium, Temperature Scales, Practical Thermometers, Expansion of Solids and Liquid.', 'Students should be able to distinguish heat and temperature. Suggested experiment/activity:
i. Calibration curve of a thermometer using the laboratory mercury thermometer as a standard. ii. Demonstration of the use of basic temperature measuring instruments.', 318::int),
    ('PHY 002', 2, '2', 'Heat and Energy', 'Heat Capacity, Specific Heat Capacity, Latent Heat, Specific Latent Heat. Thermal Conductivity, Stefan-Boltzmann’s law.', 'Students should be able to explain the concept of ‘blackbody’. Suggested experiment/activity:
i. Measurement of specific heat capacity of water or metal by mechanical and electrical methods. ii. Measurement of specific latent heat of fusion of ice. iii. Measurement of the specific latent heat of vaporization of water.', 318::int),
    ('PHY 002', 3, '3', 'Ideal gases', 'Gas Laws', 'Boyle’s law, Charles’ law, Pressure law, Dalton’s law of partial pressure.', 318::int),
    ('PHY 002', 4, NULL, NULL, 'Equation of State, K-inetic Theory of Gases, Pressure of a Gas, Kinetic Energy of a Molecule. Molecular collisions and mean free path', 'Suggested experiment/activity:
i. Verification of gas laws.', 318::int),
    ('PHY 002', 5, '4', 'Thermodynamics', 'Work Done by Gas, Internal Energy of Gas, zeroth Law of Thermodynamics, First', 'Students should be exposed to the:
i. application of thermodynamic processes.', 318::int),
    ('PHY 002', 6, NULL, NULL, 'Law of Thermodynamics, Thermodynamics processes and Second Law of Thermodynamics, Heat engines and entropy.', 'ii. Differences between Carnot cycle and Otto-cycle (refrigerators, air-conditioners, combustion engine).', 319::int),
    ('PHY 002', 7, '5', 'Waves', 'Types and properties of waves. Classification of Waves, Wave characteristics, Graphical Representation of Waves, Wave Equation, Progressive and Stationary Waves, Principle of Superposition, Interference.', 'Students should be able to distinguish between characteristics of wave (wavelength, frequency, wave speed, etc.) and properties of wave (reflection, refraction, diffraction and interference) Suggested experiment/activity:
i. Demonstration of wave using the ripple tank.', 319::int),
    ('PHY 002', 8, '6', 'Electromagnetic Waves', 'Electromagnetic Spectrum. Applications of Components of the Electromagnetic Spectrum.', 'Students should be made to understand the various components of electromagnetic spectrum according to increasing frequency or decreasing wavelength.', 319::int),
    ('PHY 002', 9, '7', 'Sound Waves', 'Pitch, Loudness, Quality, Intensity of Sound, Decibel, Echo, Beats and Application, Doppler Principle of Sound, Waves in Strings and Pipes. Nodes and antinodes', 'Suggested experiment/activity:
i. measurement of the speed of sound in air. ii. Investigation of the variation of fundamental frequency of a stretched string with length. iii. Investigation of fundamental frequency of stretched string with tension.', 319::int),
    ('PHY 002', 10, '8', 'Geometrical Optics', 'Rectilinear Propagation of Light. Laws of Reflection and Refraction, Reflection on Plane and Curved Mirrors, Refraction at Plane Surfaces, Total Internal Reflection,', 'Suggested experiment/activity:
i. Measurement of the focal length of a concave mirror. ii. Verification of Snell’s law of refraction.', 319::int),
    ('PHY 002', 11, NULL, NULL, 'Critical Angle, Dispersion by Prism.', 'iii. Measurements of the refractive index of a liquid and a solid.', 320::int),
    ('PHY 002', 12, '9', 'Lenses and Optical Instruments', 'Lenses, Formation of Images by Lenses, Lens power, the Eye, Defects of Vision. Optical Instruments (camera, refractor and reflector telescopes, simple microscope, compound microscope and ophthalmoscope).', 'Suggested experiment/activity:
i. Determination of focal length of a converging lens. Simple and compound microscope experiments. Measurement of the radius of curvature of a spherical surface using spherometer.', 320::int),
    ('PHY 002', 13, '10', 'Wave Theory of Light', 'Wave-Particle Nature of Light, Scattering of light, Huygens’ Principle. Interference and Diffraction, Coherence Sources, Young’s Double-Slit Fringes, Diffraction of Light Waves, Resolving Power, Diffraction Grating Polarization and its Applications.', 'Suggested experiment/activity:
i. Investigation of interference phenomenon – Young’s double slit experiment. ii. Experiment with diffraction – Measurement of the wavelength of a monochromatic light. iii. Measurement of the speed of light. iv. Investigation of polarization – Optical activity experiments.', 320::int),
    ('PHY 003', 1, '1', 'Electrostatics', 'Electric charge and its properties, methods of charging. Coulomb’s Law, Gauss’ Law and Applications, Concept of an Electric Field, Electric Field at a Point, Electric Potential, Electric dipoles, energy in electric field. Potential Due to a Point Charge and Charged Sphere, Relationship Between Electric Field and Electric Potential, Equipotential Surfaces.', 'Revision of electric current, potential difference, resistance and resistivity, Ohm’s law, Ohmic and non-Ohmic conductors, resistors in series and parallel are required.', 321::int),
    ('PHY 003', 2, '2', 'Capacitors', 'Capacitors and Capacitance, Dielectric and Relative Permittivity, Effects of Dielectrics, Capacitors in Series and Parallel, and Energy Stored in a Capacitor, Charging and Discharging in C-R Circuit, Time Constant.', 'Revision of charges, voltage, capacitance and dielectric is necessary.', 321::int),
    ('PHY 003', 3, '3', 'Current Electricity', 'Conductors and insulators. Electric Current, Potential Difference, Resistance and Resistivity, Ohm’s Law, Ohmic and Non-Ohmic Conductors, Resistors in Series and Parallel, Electromotive Force and Circuit, Electrical Power, Electrical Energy and Efficiency, Cells in Series and Parallel, Kirchoff’s Laws, Temperature Coefficient of Resistance, Principle of', 'Students should have pre-requisite knowledge on electric current, ohm’s law, resistivity, ohmic and non-ohmic conductors, and resistance in series and parallel. Suggested experiment/activity:
i. Verification of Joule’s law. ii. Measurement of resistivity of the material of a wire.', 321::int),
    ('PHY 003', 4, NULL, NULL, 'Potentiometer and Wheatstone Bridge, Galvanometer.', 'iii. Experimental verification of Ohm’s law. iv. Investigation of variation of resistance with temperature. v. Experiment with the Wheatstone bridge. vi. Emf and internal resistance of cells. vii. Comparison of emf – The Potentiometer. viii. Basic electro-chemistry experiments.', 322::int),
    ('PHY 003', 5, '4', 'Magnetic Field', 'Earth’s Magnetic Field, Concept of Magnetic Field. Properties of magnetic field, magnetic dipoles. Magnetic Flux and Flux-Density (of Solenoid, Straight Conductor and Narrow Circular Coil). Energy in magnetic field.', 'Students should be made to understand the concept of magnetic field and magnetic flux. Suggested experiment/activity:
Determination of the polarity of a magnet.', 322::int),
    ('PHY 003', 6, '5', 'Force on Conductor and Moving Charge', 'Force on a Current-Carrying Conductor, Force on a Moving Charge, Force Between Current-Carrying Conductors, Fleming’s Left-Hand Rule, Torque, Application to Moving-Coil Meters, Ampere’s Law, Biot-Savart’s Law. Lorentz force', 'Students should be able to state Fleming’s left-hand rule, Ampere’s law and Biot-Savart’s law.', 322::int),
    ('PHY 003', 7, '6', 'Electromagnetic Induction', 'Faraday’s Law, Lenz Law, Fleming Right-Hand Rule, Dynamo, Transformer, Eddy Current, Current in L-R Circuit,', 'Students should be able to state Fleming’s right-hand rule, Faraday’s law and Lenz law.', 322::int),
    ('PHY 003', 8, NULL, NULL, 'Self and Mutual Inductance, Energy in Coil, Motors and Generators.', NULL, 323::int),
    ('PHY 003', 9, '7', 'Alternating Current (A.C) Circuit', 'Characteristics of Alternating Current, Resistive Circuit, Capacitive Circuit, Inductive Circuit, Capacitance-Resistance Circuit, Inductance-Resistance Circuit, L-C-R Series Circuit, Resonance L-C-R Circuit, Power in A.C Circuits, Parallel Circuit.', 'Students should be able to explain period, frequency, peak value and Root-Mean-Square value as applied to an alternating current and voltage. Students should be exposed to the concept of admittance and susceptance. Suggested experiment/activity:
Alternating currents – The R-L-C circuits.', 323::int),
    ('PHY 004', 1, '1', 'Atomic Structure', 'The Nucleus (proton and neutron), The Electron, Specific Charge, Isotopes, Millikan’s Experiment, Cathode Ray Oscilloscope, Types of Spectrum, Spectra Series.', 'Revision on the basic concepts of atomic structure. Students should be made to describe the Hydrogen Spectrum. Suggested experiment/activity:
i. Geiger-Marsden experiment. ii. Experiment with mass spectrometer. iii. Millikan’s Oil Drop Experiment
– determination of e/m ratio.', 324::int),
    ('PHY 004', 2, '2', 'Elements of Modern Physics', 'Defect of the Wave Theory, Blackbody radiation, The Ultraviolet Catastrophe, Photo-Electric Emission, Thermionic Emission, Bohr’s Theory of the Hydrogen Atom and Energy Levels of the Atom, Excitation, Fraunhofer Lines. Interaction of Radiation with Matter, Laser Principle.', 'Students should be able to differentiate between Photoelectric emission and thermionic emission.', 324::int),
    ('PHY 004', 3, '3', 'X-Rays', 'Nature and Properties of X-Rays, Crystal Diffraction, Bragg’s Law, Moseley’s Law, X-Ray Spectrum, Minimum Wavelength Value. X-Ray Absorption Spectra.', 'Revision of X-ray production and the main features of modern X-ray tube.', 324::int),
    ('PHY 004', 4, '4', 'Wave-Particle Duality', 'Duality, Electron Diffraction, De Broglie Formula. Momentum and Energy, Compton Effect. Heisenberg’s Uncertainty Principle.', 'Students should be able to explain the dual nature of light (as a wave and as a particle).', 324::int),
    ('PHY 004', 5, '5', 'Radioactivity and Nuclear Energy', 'Radioactivity, Mass Defect and Nuclear Binding Energy, Nuclear Reactions, Nuclear Fission and Nuclear Fusion,', 'Suggested experiment/activity:
i. Use of basic radiation detection instruments.', 324::int),
    ('PHY 004', 6, NULL, NULL, 'Geiger-Muller Tube, Radioactive Decay – Half-Life and Decay Constant. Isotopes. Nuclear Energy, Einstein Mass-Energy Relation.', 'ii. Measurement of half-life.', 325::int),
    ('PHY 004', 7, '6', 'Introduction to Semiconductors', 'Semiconductors: Types, Energy Bands, Doping; p-n Junction Diodes, Half and Full Wave Rectification, The Bridge as a Rectifier. Transistor as an Amplifier and a Switch.', 'i. Simple model of band theory in Solids, temperature dependence of resistance of metals and intrinsic semiconductors. ii. Simple application and operation of semiconductors is required. Suggested experiment/activity:
i. Basic semiconductor diode characteristics.', 325::int),
    ('PHY 004', 8, '7', 'Applied Physics', 'Basic Applications of Physics to the Life Sciences. Fundamental Principles and Applications of Ultrasound, X-Ray and Nuclear Magnetic Resonance. Power generation: Solar, geothermal, tidal, etc.', 'Purpose and principle of CT scan should be treated. Basic applications of Physics to power generation required.', 325::int)
  ) AS v(code, ord, sn, topic, sub_topic, details, page)
  JOIN jupeb.subject_unit u ON u.code = v.code AND u.board_subject_id IS NOT NULL
ON CONFLICT (unit_id, ord) DO UPDATE SET sn = EXCLUDED.sn, topic = EXCLUDED.topic, sub_topic = EXCLUDED.sub_topic, details = EXCLUDED.details, source_page = EXCLUDED.source_page;

-- ── 4 · an either/or subject: the option the student takes ─────────────────────────────────────────────────────
ALTER TABLE jupeb.subject_registration ADD COLUMN board_subject_id uuid NULL REFERENCES jupeb.board_subject(id);
COMMENT ON COLUMN jupeb.subject_registration.board_subject_id IS 'V353: of a subject taught as one of two (Christian or Islamic Religious Studies, Igbo or Yoruba), the one the student takes; empty until chosen.';

CREATE OR REPLACE FUNCTION jupeb.registration_option()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.board_subject_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM jupeb.board_subject b WHERE b.id = NEW.board_subject_id AND b.subject_id = NEW.subject_id) THEN
        RAISE EXCEPTION 'JUPEB_OPTION: that is not taught as %', (SELECT title FROM jupeb.subject WHERE id = NEW.subject_id) USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_jupeb_registration_option BEFORE INSERT OR UPDATE OF board_subject_id, subject_id ON jupeb.subject_registration
    FOR EACH ROW EXECUTE FUNCTION jupeb.registration_option();

/* the option of an either/or subject: the student chooses until their examination number is assigned; the JUPEB Office
   at any time, with a reason when it changes one already chosen; on the application's trail */
CREATE OR REPLACE FUNCTION jupeb.choose_option(p_app uuid, p_subject uuid, p_board uuid, p_office boolean, p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE a jupeb.application; r jupeb.subject_registration; b jupeb.board_subject; was text; v_subject text;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app;
    IF a.id IS NULL THEN RAISE EXCEPTION 'JUPEB_OPTION: no such application' USING ERRCODE = '23514'; END IF;
    SELECT * INTO r FROM jupeb.subject_registration WHERE application_id = p_app AND subject_id = p_subject FOR UPDATE;
    v_subject := (SELECT title FROM jupeb.subject WHERE id = p_subject);
    IF r.id IS NULL THEN
        RAISE EXCEPTION 'JUPEB_OPTION_NOT_REGISTERED: % is not among the registered subjects', coalesce(v_subject, 'that subject') USING ERRCODE = '23514';
    END IF;
    SELECT * INTO b FROM jupeb.board_subject WHERE id = p_board;
    IF b.id IS NULL OR b.subject_id <> p_subject THEN
        RAISE EXCEPTION 'JUPEB_OPTION: that is not taught as %', v_subject USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM jupeb.board_subject x WHERE x.subject_id = p_subject AND x.syllabus_id = b.syllabus_id AND x.id <> b.id) THEN
        RAISE EXCEPTION 'JUPEB_OPTION_NONE: % has no options to choose between', v_subject USING ERRCODE = '23514';
    END IF;
    IF r.board_subject_id = p_board THEN RETURN; END IF;
    IF NOT p_office AND a.exam_no IS NOT NULL THEN
        RAISE EXCEPTION 'JUPEB_OPTION_LOCKED: your examination number is assigned; the JUPEB Office changes the option now' USING ERRCODE = '23514';
    END IF;
    IF p_office AND r.board_subject_id IS NOT NULL AND length(btrim(coalesce(p_reason, ''))) < 5 THEN
        RAISE EXCEPTION 'JUPEB_OPTION_REASON: say why the option is changed' USING ERRCODE = '23514';
    END IF;
    was := (SELECT title || ' (' || prefix || ')' FROM jupeb.board_subject WHERE id = r.board_subject_id);
    UPDATE jupeb.subject_registration SET board_subject_id = p_board WHERE id = r.id;
    PERFORM jupeb.app_event(p_app, 'SUBJECT_OPTION', v_subject || ': ' || b.title || ' (' || b.prefix || ')' || coalesce(' — was ' || was, '')
        || coalesce(' — ' || nullif(btrim(coalesce(p_reason, '')), ''), ''));
END $$;

-- ── 5 · the courses of a combination, and of a student ──────────────────────────────────────────────────────────
/* the units of the combination's three subjects (a student's registered subjects when p_app is given): the alternative for
   the combination's area, and of an either/or subject the option chosen (both until chosen) */
CREATE OR REPLACE FUNCTION jupeb.units_for(p_combination uuid, p_app uuid)
RETURNS TABLE (subject_id uuid, subject_code text, subject_title text, n int, board_subject_id uuid, board_code text, board_title text, prefix text,
               either boolean, chosen boolean, unit_id uuid, code text, title text, semester int, credit_units int, ord int, topics int)
LANGUAGE sql STABLE AS $$
    WITH c AS (SELECT * FROM jupeb.combination WHERE id = p_combination),
    reg AS (SELECT r.subject_id, r.board_subject_id FROM jupeb.subject_registration r WHERE p_app IS NOT NULL AND r.application_id = p_app),
    subj AS (SELECT x.subject_id, x.n FROM c CROSS JOIN LATERAL (VALUES (c.subject1, 1), (c.subject2, 2), (c.subject3, 3)) x(subject_id, n)
              WHERE NOT EXISTS (SELECT 1 FROM reg)
             UNION ALL
             SELECT reg.subject_id, (row_number() OVER (ORDER BY s.title))::int FROM reg JOIN jupeb.subject s ON s.id = reg.subject_id)
    SELECT s.id, s.code, s.title, subj.n, b.id, b.code, b.title, b.prefix,
           coalesce(EXISTS (SELECT 1 FROM jupeb.board_subject b2 WHERE b2.subject_id = s.id AND b2.syllabus_id = b.syllabus_id AND b2.id <> b.id), false),
           coalesce(reg.board_subject_id = b.id, false),
           u.id, u.code, u.title, u.semester, u.credit_units, u.ord, (SELECT count(*)::int FROM jupeb.unit_topic t WHERE t.unit_id = u.id)
      FROM subj JOIN jupeb.subject s ON s.id = subj.subject_id
      JOIN jupeb.subject_unit u ON u.subject_id = s.id
      LEFT JOIN jupeb.board_subject b ON b.id = u.board_subject_id
      LEFT JOIN reg ON reg.subject_id = s.id
      LEFT JOIN c ON true
     WHERE (u.areas IS NULL OR c.area IS NULL OR c.area = ANY (u.areas))
       AND (reg.board_subject_id IS NULL OR u.board_subject_id IS NULL OR u.board_subject_id = reg.board_subject_id)
     ORDER BY subj.n, u.semester NULLS LAST, b.code NULLS LAST, u.ord, u.code
$$;
COMMENT ON FUNCTION jupeb.units_for(uuid, uuid) IS 'V353: the course units of a combination (or of a student''s registered subjects): MAT 004A or 004B by the combination''s area; of an either/or subject the option chosen, both until chosen.';

-- ── 6 · the timetable names its courses as the syllabus does, and keeps the unit each is ─────────────────────────
ALTER TABLE jupeb.timetable_slot DROP CONSTRAINT ck_jupeb_slot_course;
ALTER TABLE jupeb.timetable_slot ADD CONSTRAINT ck_jupeb_slot_course CHECK (course_code IS NULL OR course_code ~ '^[A-Z]{2,4}(/[A-Z]{2,4})? [0-9]{3}[A-Z]?$');
ALTER TABLE jupeb.timetable_slot ADD COLUMN unit_id uuid NULL REFERENCES jupeb.subject_unit(id);

/* V351's rule (a room, or a named class, never twice in an hour), and now: a course code, when the subject's units are
   listed, is one of them and taught in the slot's semester — checked when the code, subject or semester changes */
CREATE OR REPLACE FUNCTION jupeb.slot_clash()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE u jupeb.subject_unit;
BEGIN
    IF NEW.course_code IS NOT NULL THEN NEW.course_code := upper(regexp_replace(btrim(NEW.course_code), '^([A-Z/]+) ?([0-9]{3}[A-Z]?)$', '\1 \2', 'i')); END IF;
    IF TG_OP = 'INSERT' OR NEW.course_code IS DISTINCT FROM OLD.course_code OR NEW.subject_id IS DISTINCT FROM OLD.subject_id OR NEW.semester IS DISTINCT FROM OLD.semester THEN
        NEW.unit_id := NULL;
        IF NEW.course_code IS NOT NULL AND EXISTS (SELECT 1 FROM jupeb.subject_unit x WHERE x.subject_id = NEW.subject_id) THEN
            SELECT * INTO u FROM jupeb.subject_unit x WHERE x.subject_id = NEW.subject_id AND x.code = NEW.course_code;
            IF u.id IS NULL THEN
                RAISE EXCEPTION 'JUPEB_SLOT_COURSE: % is not a course of % (its courses are %)', NEW.course_code, (SELECT title FROM jupeb.subject WHERE id = NEW.subject_id),
                    (SELECT string_agg(x.code, ', ' ORDER BY x.semester NULLS LAST, x.ord, x.code) FROM jupeb.subject_unit x WHERE x.subject_id = NEW.subject_id)
                    USING ERRCODE = '23514';
            END IF;
            IF u.semester IS NOT NULL AND u.semester <> NEW.semester THEN
                RAISE EXCEPTION 'JUPEB_SLOT_SEMESTER: % is taught in the % semester', u.code, CASE u.semester WHEN 1 THEN 'first' ELSE 'second' END USING ERRCODE = '23514';
            END IF;
            NEW.unit_id := u.id;
        END IF;
    END IF;
    IF NEW.active AND EXISTS (
        SELECT 1 FROM jupeb.timetable_slot s
         WHERE s.id <> NEW.id AND s.active AND s.session = NEW.session AND s.semester = NEW.semester AND s.weekday = NEW.weekday
           AND s.starts_at < NEW.ends_at AND NEW.starts_at < s.ends_at
           AND ((NEW.venue IS NOT NULL AND s.venue IS NOT NULL
                 AND upper(regexp_replace(s.venue, '\s', '', 'g')) = upper(regexp_replace(NEW.venue, '\s', '', 'g')))
                OR (NEW.class_id IS NOT NULL AND s.class_id = NEW.class_id))) THEN
        RAISE EXCEPTION 'JUPEB_SLOT_CLASH: the room (or the class) already has a lecture at that time' USING ERRCODE = '23514';
    END IF;
    NEW.updated_at := now();
    RETURN NEW;
END $$;

-- the codes as the syllabus prints them (only where that course is listed), then every slot linked to its unit
UPDATE jupeb.timetable_slot t SET course_code = v.board || substr(t.course_code, 4)
  FROM (VALUES ('ECO', 'ECN'), ('GEO', 'GRY'), ('HIS', 'HST'), ('MTH', 'MAT'), ('VAR', 'VSA')) v(portal, board)
 WHERE t.course_code LIKE v.portal || ' %' AND v.portal <> v.board
   AND EXISTS (SELECT 1 FROM jupeb.subject_unit u WHERE u.subject_id = t.subject_id AND u.code = v.board || substr(t.course_code, 4));
UPDATE jupeb.timetable_slot t SET unit_id = u.id
  FROM jupeb.subject_unit u WHERE u.subject_id = t.subject_id AND u.code = t.course_code AND t.unit_id IS NULL;

-- ── 7 · the read-only and admissions roles reach the new tables, as they reach the others ───────────────────────
GRANT SELECT ON jupeb.syllabus, jupeb.board_subject, jupeb.unit_topic TO app_auditor;
GRANT SELECT, INSERT, UPDATE ON jupeb.syllabus, jupeb.board_subject, jupeb.unit_topic TO app_admissions;

COMMIT;

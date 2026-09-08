-- ════════════════════════════════════════════════════════════════════════
--  V011  ·  The candidates a CAPS list was read with and NOT loaded.
--
--  The cut-off comes from the session's admission settings — the
--  programme's own, else its faculty's (admissions.cutoff_for), and
--  nothing is loaded while no settings are in force. A UTME candidate
--  whose aggregate is under that cut-off is not put on the register.
--
--  But "not loaded" must not mean "vanished". A parent with a CAPS
--  printout will ask why their child is not on the list, and the answer
--  has to be on record: this batch, this number, this aggregate, this
--  cut-off, this rule. So the rows held back are kept beside the batch
--  they came in, as JAMB sent them, with the reason.
-- ════════════════════════════════════════════════════════════════════════

CREATE TABLE admissions.caps_row_excluded (
    id            uuid  PRIMARY KEY,
    batch_id      uuid  NOT NULL REFERENCES admissions.caps_batch(id),
    session       text  NOT NULL,
    jamb_reg_no   text  NOT NULL,
    jamb_code     text  NOT NULL,
    surname       text  NOT NULL,
    other_names   text  NOT NULL,
    aggregate     int   NULL,
    cutoff        int   NOT NULL,
    reason        text  NOT NULL,
    raw           jsonb NOT NULL,
    CONSTRAINT ck_excl_reason CHECK (reason IN ('BELOW_CUTOFF')),
    CONSTRAINT ck_excl_code   CHECK (jamb_code ~ '^C[0-9]{5}$'),
    CONSTRAINT uq_excl_per_batch UNIQUE (batch_id, jamb_reg_no)
);

COMMENT ON TABLE admissions.caps_row_excluded IS
'Rows of a CAPS list read with the batch and not loaded, with the cut-off that '
'applied and the reason. Kept so that "why is my child not on the list" has an '
'answer on record.';

-- The same exemption as admissions.caps_row, for the same reason: this is
-- what JAMB sent, held as evidence, written once with the batch and never
-- edited. The batch row is the audited act.
SELECT audit.exempt('admissions.caps_row_excluded',
    'Evidence of a read, written once with its batch; the batch is the audited act');

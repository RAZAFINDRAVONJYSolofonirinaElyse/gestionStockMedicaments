-- ============================================================
-- GestiMed Pro — Script de création PostgreSQL
-- Version : 1.0
-- Description : Système de gestion de pharmacie
-- ============================================================




-- Extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "unaccent";

-- ============================================================
-- Types ENUM
-- ============================================================

CREATE TYPE role_utilisateur AS ENUM (
    'admin',
    'caissier'
);

CREATE TYPE statut_lot AS ENUM (
    'actif',
    'epuise',
    'retire',
    'expire'
);

CREATE TYPE type_mouvement AS ENUM (
    'entree',
    'sortie',
    'ajustement',
    'retrait',
    'inventaire'
);

CREATE TYPE mode_paiement AS ENUM (
    'especes',
    'mobile money',
    'carte',
    'cheque'
);

CREATE TYPE statut_vente AS ENUM (
    'payee',
    'attente',
    'rembourse',
    'annule'
);

CREATE TYPE statut_commande AS ENUM (
    'brouillon',
    'confirmee',
    'en_transit',
    'partiellement_livree',
    'livree',
    'annulee'
);

CREATE TYPE type_alerte AS ENUM (
    'stock_faible',
    'rupture',
    'expiration_proche',
    'lot_expire',
    'lot_retire'
);

-- ============================================================
-- TABLE : pharmacie
-- ============================================================

CREATE TABLE pharmacie (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    nom             VARCHAR(200)    NOT NULL,
    adresse         TEXT,
    ville           VARCHAR(100),
    telephone       VARCHAR(20),
    email           VARCHAR(150),
    numero_licence  VARCHAR(50),
    logo_url        TEXT,
    actif           BOOLEAN         NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- ============================================================
-- TABLE : utilisateur
-- ============================================================

CREATE TABLE utilisateur (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    pharmacie_id        UUID            NOT NULL REFERENCES pharmacie(id) ON DELETE CASCADE,
    nom                 VARCHAR(100)    NOT NULL,
    prenom              VARCHAR(100)    NOT NULL,
    email               VARCHAR(150)    NOT NULL,
    mot_de_passe_hash   VARCHAR(255)    NOT NULL,
    role                role_utilisateur NOT NULL DEFAULT 'caissier',
    actif               BOOLEAN         NOT NULL DEFAULT true,
    derniere_connexion  TIMESTAMPTZ,
    reset_token         VARCHAR(255),
    reset_token_expire  TIMESTAMPTZ,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT utilisateur_email_unique UNIQUE (email)
);

-- ============================================================
-- TABLE : fournisseur
-- ============================================================

CREATE TABLE fournisseur (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    pharmacie_id        UUID            NOT NULL REFERENCES pharmacie(id) ON DELETE CASCADE,
    nom                 VARCHAR(200)    NOT NULL,
    contact             VARCHAR(200),
    email               VARCHAR(150),
    telephone           VARCHAR(30),
    adresse             TEXT,
    ville               VARCHAR(100),
    pays                VARCHAR(100)    NOT NULL DEFAULT 'Madagascar',
    note_evaluation     DECIMAL(3,2)    CHECK (note_evaluation BETWEEN 0 AND 5),
    actif               BOOLEAN         NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- ============================================================
-- TABLE : medicament
-- ============================================================

CREATE TABLE medicament (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    pharmacie_id            UUID            NOT NULL REFERENCES pharmacie(id) ON DELETE CASCADE,
    fournisseur_principal_id UUID           REFERENCES fournisseur(id) ON DELETE SET NULL,
    nom_commercial          VARCHAR(200)    NOT NULL,
    dci                     VARCHAR(200)    NOT NULL,
    forme                   VARCHAR(50)     NOT NULL,
    dosage                  VARCHAR(100)    NOT NULL,
    categorie               VARCHAR(100)    NOT NULL,
    code_barre              VARCHAR(50),
    code_cip                VARCHAR(20),
    ordonnance_requise      BOOLEAN         NOT NULL DEFAULT false,
    prix_achat_ht           DECIMAL(12,2)   NOT NULL CHECK (prix_achat_ht >= 0),
    prix_vente_ttc          DECIMAL(12,2)   NOT NULL CHECK (prix_vente_ttc >= 0),
    tva_pct                 DECIMAL(5,2)    NOT NULL DEFAULT 20.00,
    stock_minimum           INT             NOT NULL DEFAULT 10 CHECK (stock_minimum >= 0),
    stock_maximum           INT             NOT NULL DEFAULT 500,
    unite_conditionnement   VARCHAR(50)     NOT NULL DEFAULT 'boite',
    contenance_unite        INT             NOT NULL DEFAULT 1,
    description             TEXT,
    actif                   BOOLEAN         NOT NULL DEFAULT true,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT medicament_stock_check    CHECK (stock_maximum >= stock_minimum),
    CONSTRAINT medicament_prix_check     CHECK (prix_vente_ttc >= prix_achat_ht),
    CONSTRAINT medicament_barre_unique   UNIQUE (pharmacie_id, code_barre),
    CONSTRAINT medicament_cip_unique     UNIQUE (pharmacie_id, code_cip)
);

-- ============================================================
-- TABLE : lot  ← entité clé, obligatoire pour tout médicament
-- ============================================================

CREATE TABLE lot (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    medicament_id           UUID            NOT NULL REFERENCES medicament(id) ON DELETE RESTRICT,
    fournisseur_id          UUID            REFERENCES fournisseur(id) ON DELETE SET NULL,
    numero_lot              VARCHAR(100)    NOT NULL,
    code_lot_fournisseur    VARCHAR(100),
    date_fabrication        DATE,
    date_expiration         DATE            NOT NULL,
    quantite_initiale       INT             NOT NULL CHECK (quantite_initiale > 0),
    quantite_restante       INT             NOT NULL CHECK (quantite_restante >= 0),
    statut                  statut_lot      NOT NULL DEFAULT 'actif',
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT lot_quantite_check        CHECK (quantite_restante <= quantite_initiale),
    CONSTRAINT lot_dates_check           CHECK (date_fabrication IS NULL OR date_fabrication <= date_expiration),
    CONSTRAINT lot_numero_unique         UNIQUE (medicament_id, numero_lot)
);

-- ============================================================
-- TABLE : vente
-- ============================================================

CREATE TABLE vente (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    pharmacie_id    UUID            NOT NULL REFERENCES pharmacie(id) ON DELETE CASCADE,
    caissier_id     UUID            NOT NULL REFERENCES utilisateur(id) ON DELETE RESTRICT,
    numero_ticket   VARCHAR(50)     NOT NULL,
    mode_paiement   mode_paiement   NOT NULL DEFAULT 'especes',
    montant_total   DECIMAL(12,2)   NOT NULL CHECK (montant_total >= 0),
    remise          DECIMAL(12,2)   NOT NULL DEFAULT 0 CHECK (remise >= 0),
    montant_final   DECIMAL(12,2)   NOT NULL CHECK (montant_final >= 0),
    statut          statut_vente    NOT NULL DEFAULT 'payee',
    motif_annulation TEXT,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT vente_ticket_unique     UNIQUE (pharmacie_id, numero_ticket),
    CONSTRAINT vente_remise_max_check  CHECK (remise <= montant_total)
);

-- ============================================================
-- TABLE : ligne_vente
-- ============================================================

CREATE TABLE ligne_vente (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    vente_id        UUID            NOT NULL REFERENCES vente(id) ON DELETE CASCADE,
    lot_id          UUID            NOT NULL REFERENCES lot(id) ON DELETE RESTRICT,
    quantite        INT             NOT NULL CHECK (quantite > 0),
    prix_unitaire   DECIMAL(12,2)   NOT NULL CHECK (prix_unitaire >= 0),
    sous_total      DECIMAL(12,2)   NOT NULL CHECK (sous_total >= 0),

    CONSTRAINT ligne_vente_sous_total_calc_check CHECK (
        ABS(sous_total - (quantite * prix_unitaire)) < 0.01
    )
);

-- ============================================================
-- TABLE : commande
-- ============================================================

CREATE TABLE commande (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    pharmacie_id            UUID            NOT NULL REFERENCES pharmacie(id) ON DELETE CASCADE,
    fournisseur_id          UUID            NOT NULL REFERENCES fournisseur(id) ON DELETE RESTRICT,
    createur_id             UUID            NOT NULL REFERENCES utilisateur(id) ON DELETE RESTRICT,
    numero_commande         VARCHAR(50)     NOT NULL,
    statut                  statut_commande NOT NULL DEFAULT 'brouillon',
    montant_total           DECIMAL(12,2)   NOT NULL DEFAULT 0 CHECK (montant_total >= 0),
    date_livraison_prevue   DATE,
    date_livraison_reelle   DATE,
    notes                   TEXT,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT commande_numero_unique UNIQUE (pharmacie_id, numero_commande)
);

-- ============================================================
-- TABLE : ligne_commande
-- ============================================================

CREATE TABLE ligne_commande (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    commande_id         UUID            NOT NULL REFERENCES commande(id) ON DELETE CASCADE,
    medicament_id       UUID            NOT NULL REFERENCES medicament(id) ON DELETE RESTRICT,
    quantite_commandee  INT             NOT NULL CHECK (quantite_commandee > 0),
    quantite_recue      INT             NOT NULL DEFAULT 0 CHECK (quantite_recue >= 0),
    prix_unitaire       DECIMAL(12,2)   NOT NULL CHECK (prix_unitaire >= 0),
    sous_total          DECIMAL(12,2)   GENERATED ALWAYS AS (quantite_commandee * prix_unitaire) STORED,

    CONSTRAINT ligne_commande_recue_check CHECK (quantite_recue <= quantite_commandee)
);

-- ============================================================
-- TABLE : mouvement_stock
-- ============================================================

CREATE TABLE mouvement_stock (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    lot_id          UUID            NOT NULL REFERENCES lot(id) ON DELETE RESTRICT,
    utilisateur_id  UUID            REFERENCES utilisateur(id) ON DELETE SET NULL,
    type_mouvement  type_mouvement  NOT NULL,
    quantite        INT             NOT NULL CHECK (quantite > 0),
    stock_avant     INT             NOT NULL CHECK (stock_avant >= 0),
    stock_apres     INT             NOT NULL CHECK (stock_apres >= 0),
    reference_type  VARCHAR(50),
    reference_id    UUID,
    note            TEXT,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- ============================================================
-- TABLE : alerte
-- ============================================================

CREATE TABLE alerte (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    pharmacie_id    UUID            NOT NULL REFERENCES pharmacie(id) ON DELETE CASCADE,
    lot_id          UUID            REFERENCES lot(id) ON DELETE CASCADE,
    destinataire_id UUID            REFERENCES utilisateur(id) ON DELETE SET NULL,
    type_alerte     type_alerte     NOT NULL,
    message         TEXT            NOT NULL,
    lue             BOOLEAN         NOT NULL DEFAULT false,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- ============================================================
-- TABLE : refresh_token  (gestion sessions JWT)
-- ============================================================

CREATE TABLE refresh_token (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    utilisateur_id  UUID            NOT NULL REFERENCES utilisateur(id) ON DELETE CASCADE,
    token_hash      VARCHAR(255)    NOT NULL UNIQUE,
    expire_at       TIMESTAMPTZ     NOT NULL,
    revoque         BOOLEAN         NOT NULL DEFAULT false,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- ============================================================
-- unaccent IMMUTABLE wrapper (requis pour les index sur expression)
-- ============================================================

CREATE OR REPLACE FUNCTION unaccent_immutable(text)
RETURNS text AS $$
BEGIN
    RETURN unaccent($1);
END;
$$ LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE;

-- ============================================================
-- INDEX
-- ============================================================

-- medicament
CREATE INDEX idx_med_pharmacie        ON medicament(pharmacie_id);
CREATE INDEX idx_med_categorie        ON medicament(categorie);
CREATE INDEX idx_med_dci              ON medicament(unaccent_immutable(dci));
CREATE INDEX idx_med_nom              ON medicament(unaccent_immutable(nom_commercial));
CREATE INDEX idx_med_actif            ON medicament(actif) WHERE actif = true;
CREATE INDEX idx_med_fournisseur      ON medicament(fournisseur_principal_id);

-- lot
CREATE INDEX idx_lot_medicament       ON lot(medicament_id);
CREATE INDEX idx_lot_fournisseur      ON lot(fournisseur_id);
CREATE INDEX idx_lot_expiration       ON lot(date_expiration);
CREATE INDEX idx_lot_statut           ON lot(statut);
CREATE INDEX idx_lot_actif_med        ON lot(medicament_id, statut) WHERE statut = 'actif';

-- vente
CREATE INDEX idx_vente_pharmacie      ON vente(pharmacie_id);
CREATE INDEX idx_vente_caissier       ON vente(caissier_id);
CREATE INDEX idx_vente_created        ON vente(created_at);
CREATE INDEX idx_vente_statut         ON vente(statut);

-- ligne_vente
CREATE INDEX idx_ligne_vente_vente    ON ligne_vente(vente_id);
CREATE INDEX idx_ligne_vente_lot      ON ligne_vente(lot_id);

-- commande
CREATE INDEX idx_commande_pharmacie   ON commande(pharmacie_id);
CREATE INDEX idx_commande_fournisseur ON commande(fournisseur_id);
CREATE INDEX idx_commande_statut      ON commande(statut);
CREATE INDEX idx_commande_created     ON commande(created_at);

-- ligne_commande
CREATE INDEX idx_ligne_cmd_commande   ON ligne_commande(commande_id);
CREATE INDEX idx_ligne_cmd_med        ON ligne_commande(medicament_id);

-- mouvement_stock
CREATE INDEX idx_mvt_lot              ON mouvement_stock(lot_id);
CREATE INDEX idx_mvt_created          ON mouvement_stock(created_at);
CREATE INDEX idx_mvt_type             ON mouvement_stock(type_mouvement);
CREATE INDEX idx_mvt_ref              ON mouvement_stock(reference_type, reference_id);

-- alerte
CREATE INDEX idx_alerte_pharmacie     ON alerte(pharmacie_id);
CREATE INDEX idx_alerte_lot           ON alerte(lot_id);
CREATE INDEX idx_alerte_dest          ON alerte(destinataire_id);
CREATE INDEX idx_alerte_non_lue       ON alerte(destinataire_id, lue) WHERE lue = false;

-- refresh_token
CREATE INDEX idx_token_utilisateur    ON refresh_token(utilisateur_id);
CREATE INDEX idx_token_expire         ON refresh_token(expire_at);

-- ============================================================
-- VUE : stock_actuel  (stock calculé depuis les lots)
-- ============================================================

CREATE OR REPLACE VIEW v_stock_actuel AS
SELECT
    m.id                            AS medicament_id,
    m.pharmacie_id,
    m.nom_commercial,
    m.dci,
    m.forme,
    m.dosage,
    m.categorie,
    m.code_barre,
    m.prix_vente_ttc,
    m.stock_minimum,
    m.stock_maximum,
    COALESCE(SUM(l.quantite_restante), 0)::INT  AS stock_actuel,
    COUNT(l.id)::INT                             AS nb_lots_actifs,
    MIN(l.date_expiration)                       AS prochaine_expiration,
    CASE
        WHEN COALESCE(SUM(l.quantite_restante), 0) = 0              THEN 'rupture'
        WHEN COALESCE(SUM(l.quantite_restante), 0) < m.stock_minimum THEN 'critique'
        WHEN COALESCE(SUM(l.quantite_restante), 0) < m.stock_minimum * 1.5 THEN 'faible'
        ELSE 'normal'
    END                                          AS statut_stock
FROM medicament m
LEFT JOIN lot l ON l.medicament_id = m.id
    AND l.statut = 'actif'
    AND l.date_expiration > CURRENT_DATE
WHERE m.actif = true
GROUP BY m.id, m.pharmacie_id, m.nom_commercial, m.dci, m.forme,
         m.dosage, m.categorie, m.code_barre, m.prix_vente_ttc,
         m.stock_minimum, m.stock_maximum;

-- ============================================================
-- VUE : lots en alerte expiration (< 90 jours)
-- ============================================================

CREATE OR REPLACE VIEW v_lots_expiration AS
SELECT
    l.id                AS lot_id,
    l.numero_lot,
    l.date_expiration,
    l.quantite_restante,
    l.statut,
    m.id                AS medicament_id,
    m.nom_commercial,
    m.dci,
    m.pharmacie_id,
    (l.date_expiration - CURRENT_DATE)  AS jours_restants,
    CASE
        WHEN l.date_expiration < CURRENT_DATE                       THEN 'expire'
        WHEN l.date_expiration <= CURRENT_DATE + INTERVAL '30 days' THEN 'urgent'
        WHEN l.date_expiration <= CURRENT_DATE + INTERVAL '90 days' THEN 'proche'
        ELSE 'ok'
    END                 AS niveau_urgence
FROM lot l
JOIN medicament m ON m.id = l.medicament_id
WHERE l.statut = 'actif'
  AND l.quantite_restante > 0
  AND l.date_expiration <= CURRENT_DATE + INTERVAL '90 days'
ORDER BY l.date_expiration ASC;

-- ============================================================
-- VUE : dashboard KPIs
-- ============================================================

CREATE OR REPLACE VIEW v_dashboard_kpis AS
SELECT
    ph.id                           AS pharmacie_id,
    COUNT(DISTINCT m.id)::INT       AS nb_medicaments,
    COUNT(DISTINCT f.id)::INT       AS nb_fournisseurs,
    COALESCE(vj.ca_jour, 0)         AS ca_jour,
    COALESCE(vj.nb_ventes, 0)::INT  AS nb_ventes_jour,
    COALESCE(al.nb_alertes, 0)::INT AS nb_alertes_non_lues,
    COALESCE(sf.nb_stock_faible, 0)::INT AS nb_stock_faible
FROM pharmacie ph
LEFT JOIN medicament m ON m.pharmacie_id = ph.id AND m.actif = true
LEFT JOIN fournisseur f ON f.pharmacie_id = ph.id AND f.actif = true
LEFT JOIN LATERAL (
    SELECT SUM(montant_final) AS ca_jour,
           COUNT(*)           AS nb_ventes
    FROM vente
    WHERE pharmacie_id = ph.id
      AND statut = 'payee'
      AND DATE(created_at) = CURRENT_DATE
) vj ON true
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS nb_alertes
    FROM alerte a
    JOIN utilisateur u ON u.id = a.destinataire_id
    WHERE a.pharmacie_id = ph.id AND a.lue = false
) al ON true
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS nb_stock_faible
    FROM v_stock_actuel s
    WHERE s.pharmacie_id = ph.id
      AND s.statut_stock IN ('critique', 'rupture')
) sf ON true
GROUP BY ph.id, vj.ca_jour, vj.nb_ventes, al.nb_alertes, sf.nb_stock_faible;

-- ============================================================
-- FONCTION : auto-update updated_at
-- ============================================================

CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- FONCTION : décrémenter lot lors d'une vente
-- ============================================================

CREATE OR REPLACE FUNCTION fn_after_ligne_vente_insert()
RETURNS TRIGGER AS $$
DECLARE
    v_stock_avant INT;
BEGIN
    SELECT quantite_restante INTO v_stock_avant
    FROM lot WHERE id = NEW.lot_id FOR UPDATE;

    IF v_stock_avant < NEW.quantite THEN
        RAISE EXCEPTION 'Stock insuffisant pour le lot % (disponible: %, demandé: %)',
            NEW.lot_id, v_stock_avant, NEW.quantite;
    END IF;

    UPDATE lot
    SET quantite_restante = quantite_restante - NEW.quantite,
        statut = CASE
            WHEN quantite_restante - NEW.quantite = 0 THEN 'epuise'::statut_lot
            ELSE statut
        END,
        updated_at = NOW()
    WHERE id = NEW.lot_id;

    INSERT INTO mouvement_stock (
        lot_id, type_mouvement, quantite,
        stock_avant, stock_apres,
        reference_type, reference_id
    ) VALUES (
        NEW.lot_id, 'sortie', NEW.quantite,
        v_stock_avant, v_stock_avant - NEW.quantite,
        'vente', NEW.vente_id
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- FONCTION : réincrémenter lot si vente annulée / remboursée
-- ============================================================

CREATE OR REPLACE FUNCTION fn_after_vente_annulation()
RETURNS TRIGGER AS $$
DECLARE
    r RECORD;
BEGIN
    IF NEW.statut IN ('annule', 'rembourse') AND OLD.statut = 'payee' THEN
        FOR r IN
            SELECT lot_id, quantite FROM ligne_vente WHERE vente_id = NEW.id
        LOOP
            UPDATE lot
            SET quantite_restante = quantite_restante + r.quantite,
                statut = 'actif',
                updated_at = NOW()
            WHERE id = r.lot_id;

            INSERT INTO mouvement_stock (
                lot_id, type_mouvement, quantite,
                stock_avant, stock_apres,
                reference_type, reference_id,
                note
            )
            SELECT
                r.lot_id, 'ajustement', r.quantite,
                quantite_restante - r.quantite,
                quantite_restante,
                'vente_annulee', NEW.id,
                'Annulation vente ' || NEW.numero_ticket
            FROM lot WHERE id = r.lot_id;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- FONCTION : créer lot automatiquement à la réception commande
-- ============================================================

CREATE OR REPLACE FUNCTION fn_recalc_commande_total()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE commande
    SET montant_total = (
        SELECT COALESCE(SUM(sous_total), 0)
        FROM ligne_commande
        WHERE commande_id = COALESCE(NEW.commande_id, OLD.commande_id)
    ),
    updated_at = NOW()
    WHERE id = COALESCE(NEW.commande_id, OLD.commande_id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- FONCTION : générer alertes stock faible automatiquement
-- ============================================================

CREATE OR REPLACE FUNCTION fn_generer_alertes_stock()
RETURNS void AS $$
DECLARE
    r RECORD;
    v_admin RECORD;
BEGIN
    FOR r IN
        SELECT s.*, m.pharmacie_id
        FROM v_stock_actuel s
        JOIN medicament m ON m.id = s.medicament_id
        WHERE s.statut_stock IN ('critique', 'rupture')
    LOOP
        FOR v_admin IN
            SELECT id FROM utilisateur
            WHERE pharmacie_id = r.pharmacie_id AND role = 'admin' AND actif = true
        LOOP
            IF NOT EXISTS (
                SELECT 1 FROM alerte
                WHERE lot_id IS NULL
                  AND pharmacie_id = r.pharmacie_id
                  AND destinataire_id = v_admin.id
                  AND type_alerte = CASE WHEN r.statut_stock = 'rupture'
                                        THEN 'rupture'::type_alerte
                                        ELSE 'stock_faible'::type_alerte END
                  AND created_at > NOW() - INTERVAL '24 hours'
            ) THEN
                INSERT INTO alerte (pharmacie_id, destinataire_id, type_alerte, message)
                VALUES (
                    r.pharmacie_id,
                    v_admin.id,
                    CASE WHEN r.statut_stock = 'rupture'
                         THEN 'rupture'::type_alerte
                         ELSE 'stock_faible'::type_alerte END,
                    r.nom_commercial || ' — Stock: ' || r.stock_actuel ||
                    ' (seuil min: ' || r.stock_minimum || ')'
                );
            END IF;
        END LOOP;
    END LOOP;

    FOR r IN
        SELECT v.*, m.nom_commercial, m.pharmacie_id
        FROM v_lots_expiration v
        JOIN medicament m ON m.id = v.medicament_id
        WHERE v.niveau_urgence IN ('expire', 'urgent', 'proche')
    LOOP
        FOR v_admin IN
            SELECT id FROM utilisateur
            WHERE pharmacie_id = r.pharmacie_id AND role = 'admin' AND actif = true
        LOOP
            IF NOT EXISTS (
                SELECT 1 FROM alerte
                WHERE lot_id = r.lot_id
                  AND destinataire_id = v_admin.id
                  AND type_alerte IN ('expiration_proche', 'lot_expire')
                  AND created_at > NOW() - INTERVAL '24 hours'
            ) THEN
                INSERT INTO alerte (pharmacie_id, lot_id, destinataire_id, type_alerte, message)
                VALUES (
                    r.pharmacie_id,
                    r.lot_id,
                    v_admin.id,
                    CASE WHEN r.niveau_urgence = 'expire'
                         THEN 'lot_expire'::type_alerte
                         ELSE 'expiration_proche'::type_alerte END,
                    r.nom_commercial || ' — Lot ' || r.numero_lot ||
                    ' expire le ' || TO_CHAR(r.date_expiration, 'DD/MM/YYYY') ||
                    ' (' || r.jours_restants || ' j)'
                );
            END IF;
        END LOOP;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- TRIGGERS
-- ============================================================

-- updated_at automatique
CREATE TRIGGER trg_pharmacie_updated_at
    BEFORE UPDATE ON pharmacie
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_utilisateur_updated_at
    BEFORE UPDATE ON utilisateur
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_fournisseur_updated_at
    BEFORE UPDATE ON fournisseur
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_medicament_updated_at
    BEFORE UPDATE ON medicament
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_lot_updated_at
    BEFORE UPDATE ON lot
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_vente_updated_at
    BEFORE UPDATE ON vente
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_commande_updated_at
    BEFORE UPDATE ON commande
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- Décrémenter le stock à chaque ligne de vente insérée
CREATE TRIGGER trg_ligne_vente_stock
    AFTER INSERT ON ligne_vente
    FOR EACH ROW EXECUTE FUNCTION fn_after_ligne_vente_insert();

-- Ré-incrémenter le stock si vente annulée
CREATE TRIGGER trg_vente_annulation_stock
    AFTER UPDATE OF statut ON vente
    FOR EACH ROW EXECUTE FUNCTION fn_after_vente_annulation();

-- Recalculer le total commande à chaque ligne insérée/modifiée/supprimée
CREATE TRIGGER trg_ligne_commande_total_insert
    AFTER INSERT ON ligne_commande
    FOR EACH ROW EXECUTE FUNCTION fn_recalc_commande_total();

CREATE TRIGGER trg_ligne_commande_total_update
    AFTER UPDATE ON ligne_commande
    FOR EACH ROW EXECUTE FUNCTION fn_recalc_commande_total();

CREATE TRIGGER trg_ligne_commande_total_delete
    AFTER DELETE ON ligne_commande
    FOR EACH ROW EXECUTE FUNCTION fn_recalc_commande_total();

-- ============================================================
-- DONNÉES INITIALES
-- ============================================================

INSERT INTO pharmacie (id, nom, adresse, ville, telephone, email)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'Pharmacie GestiMed Demo',
    'Lot II M 85 Bis, Ankadifotsy',
    'Antananarivo',
    '+261 20 22 123 45',
    'contact@gestimed-demo.mg'
);

-- Admin par défaut (mot de passe: Admin@2025 — à changer)
INSERT INTO utilisateur (pharmacie_id, nom, prenom, email, mot_de_passe_hash, role)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'Administrateur',
    'GestiMed',
    'admin@gestimed.mg',
    crypt('Admin@2025', gen_salt('bf', 12)),
    'admin'
);

-- Caissier de démonstration
INSERT INTO utilisateur (pharmacie_id, nom, prenom, email, mot_de_passe_hash, role)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'Rakoto',
    'Marie',
    'marie@gestimed.mg',
    crypt('Caissier@2025', gen_salt('bf', 12)),
    'caissier'
);

-- Fournisseurs de démonstration
INSERT INTO fournisseur (pharmacie_id, nom, contact, email, telephone, pays) VALUES
('00000000-0000-0000-0000-000000000001', 'PharmaDis Madagascar', 'Jean Rabe', 'commandes@pharmadis.mg', '+261 20 22 456 78', 'Madagascar'),
('00000000-0000-0000-0000-000000000001', 'MedExpress', 'Sophie Razafy', 'orders@medexpress.mg', '+261 34 12 345 67', 'Madagascar'),
('00000000-0000-0000-0000-000000000001', 'Sogequip', 'Paul Martin', 'paul@sogequip.fr', '+33 1 42 00 00 00', 'France');

-- ============================================================
-- COMMENTAIRES
-- ============================================================

COMMENT ON TABLE medicament         IS 'Catalogue des médicaments. Le stock réel est calculé depuis la table LOT.';
COMMENT ON TABLE lot                IS 'Lots physiques — entité obligatoire. Tout médicament doit avoir au moins un lot actif pour être vendable.';
COMMENT ON TABLE mouvement_stock    IS 'Journal immuable de toutes les entrées et sorties de stock par lot.';
COMMENT ON TABLE vente              IS 'En-tête de chaque transaction POS.';
COMMENT ON TABLE ligne_vente        IS 'Détail des articles vendus — référence le LOT (pas le médicament directement).';
COMMENT ON VIEW  v_stock_actuel     IS 'Vue calculant le stock en temps réel depuis les lots actifs non expirés.';
COMMENT ON VIEW  v_lots_expiration  IS 'Lots actifs expirant dans les 90 prochains jours, triés par urgence.';
COMMENT ON VIEW  v_dashboard_kpis   IS 'Aggrégats pour les 5 cartes du tableau de bord admin.';
COMMENT ON FUNCTION fn_generer_alertes_stock IS 'À appeler par un cron job (ex: chaque nuit à 02h00) pour générer les alertes automatiques.';

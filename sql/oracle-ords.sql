CREATE TABLE APPARENT_LISTINGS (
    LISTING_ID VARCHAR2(32 CHAR) DEFAULT LOWER(RAWTOHEX(SYS_GUID())) NOT NULL,
    TITLE VARCHAR2(120 CHAR) NOT NULL,
    CATEGORY VARCHAR2(32 CHAR) NOT NULL,
    NEIGHBORHOOD VARCHAR2(32 CHAR) NOT NULL,
    OWNER_NAME VARCHAR2(80 CHAR) DEFAULT 'A neighbor' NOT NULL,
    PRICE_CENTS NUMBER(10, 0) NOT NULL,
    CONTACT VARCHAR2(500 CHAR) NOT NULL,
    EMOJI VARCHAR2(16 CHAR) DEFAULT '📦' NOT NULL,
    ART_CLASS VARCHAR2(32 CHAR) DEFAULT 'art-mint' NOT NULL,
    DESCRIPTION VARCHAR2(2000 CHAR),
    EXPIRES_AT_MS NUMBER(13, 0) NOT NULL,
    CONSTRAINT APPARENT_LISTINGS_PK PRIMARY KEY (LISTING_ID),
    CONSTRAINT APPARENT_LISTINGS_TITLE_CK CHECK (LENGTH(TRIM(TITLE)) BETWEEN 1 AND 120),
    CONSTRAINT APPARENT_LISTINGS_CATEGORY_CK CHECK (CATEGORY IN ('Tools', 'Outdoors', 'Home', 'Electronics', 'Sports')),
    CONSTRAINT APPARENT_LISTINGS_NEIGHBORHOOD_CK CHECK (NEIGHBORHOOD IN ('Maplewood', 'Riverside', 'Oak Hill')),
    CONSTRAINT APPARENT_LISTINGS_PRICE_CK CHECK (PRICE_CENTS BETWEEN 0 AND 10000000),
    CONSTRAINT APPARENT_LISTINGS_CONTACT_CK CHECK (LENGTH(TRIM(CONTACT)) BETWEEN 1 AND 500),
    CONSTRAINT APPARENT_LISTINGS_DESCRIPTION_CK CHECK (DESCRIPTION IS NULL OR LENGTH(DESCRIPTION) <= 2000)
);

CREATE INDEX APPARENT_LISTINGS_EXPIRY_IX
    ON APPARENT_LISTINGS (EXPIRES_AT_MS);

CREATE OR REPLACE TRIGGER APPARENT_LISTINGS_EXPIRY_BI
BEFORE INSERT ON APPARENT_LISTINGS
FOR EACH ROW
BEGIN
    :NEW.LISTING_ID := LOWER(RAWTOHEX(SYS_GUID()));
    :NEW.EXPIRES_AT_MS :=
        ROUND((CAST(SYSTIMESTAMP AT TIME ZONE 'UTC' AS DATE) - DATE '1970-01-01') * 86400000)
        + 604800000;
END;
/

BEGIN
    ORDS.ENABLE_SCHEMA(
        p_enabled => TRUE,
        p_schema => USER,
        p_url_mapping_type => 'BASE_PATH',
        p_url_mapping_pattern => 'apparent_owner',
        p_auto_rest_auth => FALSE
    );

    ORDS.DEFINE_MODULE(
        p_module_name => 'apparent.listings.v1',
        p_base_path => '/v1/',
        p_items_per_page => 100,
        p_status => 'PUBLISHED',
        p_comments => 'Public AppaRent listing collection'
    );

    ORDS.DEFINE_TEMPLATE(
        p_module_name => 'apparent.listings.v1',
        p_pattern => 'listings/',
        p_comments => 'Active listing collection; POST creates a listing'
    );

    ORDS.DEFINE_HANDLER(
        p_module_name => 'apparent.listings.v1',
        p_pattern => 'listings/',
        p_method => 'GET',
        p_source_type => ORDS.source_type_collection_feed,
        p_items_per_page => 100,
        p_comments => 'List active public listings',
        p_source => q'[
            SELECT listing_id AS "listing_id",
                   title AS "title",
                   category AS "category",
                   neighborhood AS "neighborhood",
                   owner_name AS "owner_name",
                   price_cents AS "price_cents",
                   contact AS "contact",
                   emoji AS "emoji",
                   art_class AS "art_class",
                   description AS "description",
                   expires_at_ms AS "expires_at_ms"
              FROM apparent_listings
             WHERE expires_at_ms >
                   ROUND((CAST(SYSTIMESTAMP AT TIME ZONE 'UTC' AS DATE) - DATE '1970-01-01') * 86400000)
             ORDER BY expires_at_ms DESC
        ]'
    );

    ORDS.DEFINE_HANDLER(
        p_module_name => 'apparent.listings.v1',
        p_pattern => 'listings/',
        p_method => 'POST',
        p_source_type => ORDS.source_type_plsql,
        p_mimes_allowed => 'application/json',
        p_comments => 'Validate and create a public listing',
        p_source => q'[
            DECLARE
                l_title VARCHAR2(120) := TRIM(:title);
                l_category VARCHAR2(32) := :category;
                l_neighborhood VARCHAR2(32) := :neighborhood;
                l_owner_name VARCHAR2(80) := NVL(NULLIF(TRIM(:owner_name), ''), 'A neighbor');
                l_price_cents NUMBER := :price_cents;
                l_contact VARCHAR2(500) := TRIM(:contact);
                l_emoji VARCHAR2(16) := NVL(:emoji, '📦');
                l_art_class VARCHAR2(32) := NVL(:art_class, 'art-mint');
                l_description VARCHAR2(2000) := :description;
            BEGIN
                IF l_title IS NULL OR LENGTH(l_title) > 120 THEN
                    RAISE_APPLICATION_ERROR(-20001, 'Title must contain 1 to 120 characters.');
                ELSIF l_category NOT IN ('Tools', 'Outdoors', 'Home', 'Electronics', 'Sports') THEN
                    RAISE_APPLICATION_ERROR(-20002, 'Invalid category.');
                ELSIF l_neighborhood NOT IN ('Maplewood', 'Riverside', 'Oak Hill') THEN
                    RAISE_APPLICATION_ERROR(-20003, 'Invalid neighborhood.');
                ELSIF l_price_cents < 0 OR l_price_cents > 10000000 THEN
                    RAISE_APPLICATION_ERROR(-20004, 'Price is outside the allowed range.');
                ELSIF l_contact IS NULL OR LENGTH(l_contact) > 500 THEN
                    RAISE_APPLICATION_ERROR(-20005, 'Contact details must contain 1 to 500 characters.');
                ELSIF LENGTH(l_owner_name) > 80 OR LENGTH(l_description) > 2000 THEN
                    RAISE_APPLICATION_ERROR(-20006, 'Listing details exceed the allowed length.');
                END IF;

                INSERT INTO apparent_listings (
                    title, category, neighborhood, owner_name, price_cents,
                    contact, emoji, art_class, description
                ) VALUES (
                    l_title, l_category, l_neighborhood, l_owner_name, l_price_cents,
                    l_contact, l_emoji, l_art_class, l_description
                );

                :status_code := 201;
            END;
        ]'
    );
END;
/

BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name => 'APPARENT_DELETE_EXPIRED',
        job_type => 'PLSQL_BLOCK',
        job_action => 'BEGIN DELETE FROM APPARENT_LISTINGS WHERE EXPIRES_AT_MS <= ROUND((CAST(SYSTIMESTAMP AT TIME ZONE ''UTC'' AS DATE) - DATE ''1970-01-01'') * 86400000); COMMIT; END;',
        start_date => SYSTIMESTAMP,
        repeat_interval => 'FREQ=HOURLY',
        enabled => TRUE,
        comments => 'Permanently remove expired AppaRent listings'
    );
END;
/

COMMIT;

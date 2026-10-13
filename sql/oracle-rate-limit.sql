-- Apply once as APPARENT_OWNER to an existing AppaRent ORDS installation.

CREATE TABLE APPARENT_POST_LIMITS (
    CLIENT_KEY RAW(32) NOT NULL,
    WINDOW_STARTED_AT TIMESTAMP WITH TIME ZONE NOT NULL,
    POST_COUNT NUMBER(1, 0) NOT NULL,
    CONSTRAINT APPARENT_POST_LIMITS_PK PRIMARY KEY (CLIENT_KEY),
    CONSTRAINT APPARENT_POST_LIMITS_COUNT_CK CHECK (POST_COUNT BETWEEN 1 AND 5)
);

CREATE OR REPLACE PACKAGE APPARENT_RATE_LIMIT AS
    FUNCTION ALLOW_POST(p_client_address IN VARCHAR2) RETURN BOOLEAN;
END APPARENT_RATE_LIMIT;
/

CREATE OR REPLACE PACKAGE BODY APPARENT_RATE_LIMIT AS
    FUNCTION ALLOW_POST(p_client_address IN VARCHAR2) RETURN BOOLEAN IS
        PRAGMA AUTONOMOUS_TRANSACTION;

        l_client_key RAW(32);
        l_window_started_at TIMESTAMP WITH TIME ZONE;
        l_post_count NUMBER;
        l_now TIMESTAMP WITH TIME ZONE := SYSTIMESTAMP;
    BEGIN
        IF p_client_address IS NULL OR TRIM(p_client_address) IS NULL THEN
            ROLLBACK;
            RETURN FALSE;
        END IF;

        SELECT STANDARD_HASH(LOWER(TRIM(p_client_address)), 'SHA256')
          INTO l_client_key
          FROM dual;

        BEGIN
            SELECT window_started_at, post_count
              INTO l_window_started_at, l_post_count
              FROM apparent_post_limits
             WHERE client_key = l_client_key
               FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                BEGIN
                    INSERT INTO apparent_post_limits (
                        client_key, window_started_at, post_count
                    ) VALUES (
                        l_client_key, l_now, 1
                    );

                    COMMIT;
                    RETURN TRUE;
                EXCEPTION
                    WHEN DUP_VAL_ON_INDEX THEN
                        SELECT window_started_at, post_count
                          INTO l_window_started_at, l_post_count
                          FROM apparent_post_limits
                         WHERE client_key = l_client_key
                           FOR UPDATE;
                END;
        END;

        IF l_window_started_at <= l_now - INTERVAL '1' HOUR THEN
            UPDATE apparent_post_limits
               SET window_started_at = l_now,
                   post_count = 1
             WHERE client_key = l_client_key;

            COMMIT;
            RETURN TRUE;
        ELSIF l_post_count < 5 THEN
            UPDATE apparent_post_limits
               SET post_count = post_count + 1
             WHERE client_key = l_client_key;

            COMMIT;
            RETURN TRUE;
        ELSE
            COMMIT;
            RETURN FALSE;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END ALLOW_POST;
END APPARENT_RATE_LIMIT;
/

BEGIN
    ORDS.DEFINE_HANDLER(
        p_module_name => 'apparent.listings.v1',
        p_pattern => 'listings/',
        p_method => 'POST',
        p_source_type => ORDS.source_type_plsql,
        p_mimes_allowed => 'application/json',
        p_comments => 'Validate and rate-limit public listing creation',
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
                IF NOT apparent_rate_limit.allow_post(OWA_UTIL.GET_CGI_ENV('REMOTE_ADDR')) THEN
                    :status_code := 429;
                ELSE
                    IF l_title IS NULL OR LENGTH(l_title) > 120 THEN
                        RAISE_APPLICATION_ERROR(-20001, 'Title must contain 1 to 120 characters.');
                    ELSIF l_category NOT IN ('Tools', 'Outdoors', 'Home', 'Electronics', 'Sports') THEN
                        RAISE_APPLICATION_ERROR(-20002, 'Invalid category.');
                    ELSIF l_neighborhood NOT IN ('Ang Mo Kio', 'Bedok', 'Bishan', 'Bukit Batok', 'Bukit Merah', 'Bukit Panjang', 'Choa Chu Kang', 'Clementi', 'Geylang', 'Hougang', 'Jurong East', 'Jurong West', 'Kallang/Whampoa', 'Marine Parade', 'Pasir Ris', 'Punggol', 'Queenstown', 'Sembawang', 'Sengkang', 'Serangoon', 'Tampines', 'Toa Payoh', 'Woodlands', 'Yishun') THEN
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
                END IF;
            END;
        ]'
    );

    DBMS_SCHEDULER.SET_ATTRIBUTE(
        name => 'APPARENT_DELETE_EXPIRED',
        attribute => 'job_action',
        value => 'BEGIN DELETE FROM APPARENT_LISTINGS WHERE EXPIRES_AT_MS <= ROUND((CAST(SYSTIMESTAMP AT TIME ZONE ''UTC'' AS DATE) - DATE ''1970-01-01'') * 86400000); DELETE FROM APPARENT_POST_LIMITS WHERE WINDOW_STARTED_AT <= SYSTIMESTAMP - INTERVAL ''1'' HOUR; COMMIT; END;'
    );
END;
/

COMMIT;

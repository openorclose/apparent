-- Apply once as APPARENT_OWNER after the listing schema and rate limit are installed.
-- Existing fictional-town listings are deleted because they cannot be assigned
-- to a real Singapore town without guessing the sharer's location.

ALTER TABLE APPARENT_LISTINGS
    DROP CONSTRAINT APPARENT_LISTINGS_NEIGHBORHOOD_CK;

DELETE FROM APPARENT_LISTINGS
 WHERE TRIM(NEIGHBORHOOD) NOT IN (
    'Ang Mo Kio', 'Bedok', 'Bishan', 'Bukit Batok', 'Bukit Merah',
    'Bukit Panjang', 'Choa Chu Kang', 'Clementi', 'Geylang', 'Hougang',
    'Jurong East', 'Jurong West', 'Kallang/Whampoa', 'Marine Parade',
    'Pasir Ris', 'Punggol', 'Queenstown', 'Sembawang', 'Sengkang',
    'Serangoon', 'Tampines', 'Toa Payoh', 'Woodlands', 'Yishun'
 );

ALTER TABLE APPARENT_LISTINGS
    ADD CONSTRAINT APPARENT_LISTINGS_NEIGHBORHOOD_CK
    CHECK (NEIGHBORHOOD IN (
        'Ang Mo Kio', 'Bedok', 'Bishan', 'Bukit Batok', 'Bukit Merah',
        'Bukit Panjang', 'Choa Chu Kang', 'Clementi', 'Geylang', 'Hougang',
        'Jurong East', 'Jurong West', 'Kallang/Whampoa', 'Marine Parade',
        'Pasir Ris', 'Punggol', 'Queenstown', 'Sembawang', 'Sengkang',
        'Serangoon', 'Tampines', 'Toa Payoh', 'Woodlands', 'Yishun'
    ));

BEGIN
    ORDS.DEFINE_HANDLER(
        p_module_name => 'apparent.listings.v1',
        p_pattern => 'listings/',
        p_method => 'POST',
        p_source_type => ORDS.source_type_plsql,
        p_mimes_allowed => 'application/json',
        p_comments => 'Validate and rate-limit public listing creation in Singapore towns',
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
                        RAISE_APPLICATION_ERROR(-20003, 'Choose a supported Singapore town.');
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
END;
/

COMMIT;

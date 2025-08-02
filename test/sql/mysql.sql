DROP TABLE ACCOUNT_TEST;
CREATE TABLE ACCOUNT_TEST
(
	USER_ID INT PRIMARY KEY AUTO_INCREMENT,
	USERNAME VARCHAR(50) UNIQUE NOT NULL,
	PASSWORD VARCHAR(50) NOT NULL,
	EMAIL VARCHAR(355) UNIQUE NOT NULL,
	CREATED_ON TIMESTAMP NOT NULL DEFAULT NOW(),
	LAST_LOGIN TIMESTAMP DEFAULT NOW()
);

-- Basic inserts with different timestamp patterns
INSERT INTO ACCOUNT_TEST (USERNAME, PASSWORD, EMAIL, CREATED_ON, LAST_LOGIN)
VALUES ('john_doe', 'pass123', 'john@example.com', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

INSERT INTO ACCOUNT_TEST (USERNAME, PASSWORD, EMAIL, CREATED_ON, LAST_LOGIN)
VALUES ('jane_smith', 'secure456', 'jane@example.com', '2024-01-01 10:00:00', '2024-01-01 10:30:00');

INSERT INTO ACCOUNT_TEST (USERNAME, PASSWORD, EMAIL, CREATED_ON)
VALUES ('new_user', 'welcome789', 'new@example.com', CURRENT_TIMESTAMP);

-- Batch insert
INSERT INTO ACCOUNT_TEST (USERNAME, PASSWORD, EMAIL, CREATED_ON, LAST_LOGIN)
VALUES
    ('alice_wonder', 'alice123', 'alice@example.com', '2024-02-15 08:30:00', '2024-02-15 09:00:00'),
    ('bob_builder', 'bob456', 'bob@example.com', '2024-02-15 09:15:00', '2024-02-15 10:00:00');

-- Simple select statements
SELECT * FROM ACCOUNT_TEST WHERE LAST_LOGIN IS NOT NULL;
SELECT USERNAME, EMAIL, CREATED_ON FROM ACCOUNT_TEST ORDER BY CREATED_ON DESC;
SELECT COUNT(*) as active_users FROM ACCOUNT_TEST WHERE LAST_LOGIN >= NOW() - INTERVAL '1 day';

-- Update statements with timestamp handling
UPDATE ACCOUNT_TEST
SET LAST_LOGIN = NOW()
WHERE USERNAME = 'john_doe';

UPDATE ACCOUNT_TEST
SET PASSWORD = 'newpass123',
    LAST_LOGIN = NOW()
WHERE EMAIL = 'jane@example.com';

-- Select to verify updates
SELECT USERNAME, LAST_LOGIN
FROM ACCOUNT_TEST
WHERE USERNAME IN ('john_doe', 'jane_smith')
ORDER BY LAST_LOGIN DESC;

-- Add long data entries to test word wrap functionality
INSERT INTO ACCOUNT_TEST (USERNAME, PASSWORD, EMAIL, CREATED_ON, LAST_LOGIN)
VALUES ('very_long_username_that_should_definitely_cause_word_wrap_when_displayed_in_results_table_this_is_really_quite_long',
        'extremely_long_password_with_many_characters_that_extends_beyond_normal_screen_width_causing_horizontal_scrolling_or_word_wrapping_functionality_to_be_tested_thoroughly',
        'this_is_an_extremely_long_email_address_that_goes_on_and_on_and_should_definitely_cause_word_wrap_issues_when_displayed@very-long-domain-name-for-testing-purposes-only.example.com',
        '2024-03-01 12:00:00',
        '2024-03-01 12:30:00');

INSERT INTO ACCOUNT_TEST (USERNAME, PASSWORD, EMAIL, CREATED_ON, LAST_LOGIN)
VALUES ('another_user_with_really_long_name_for_comprehensive_word_wrap_testing_purposes_in_sqlflick_plugin',
        'password_that_is_intentionally_made_very_long_to_test_how_the_display_handles_extensive_text_content_overflow',
        'super.long.email.address.with.many.dots.and.subdomains.for.testing.word.wrap.behavior@extremely-long-subdomain.testing-domain.example.org',
        '2024-03-02 14:15:30',
        '2024-03-02 15:45:22');

-- Long SELECT query to test word wrap in query display
SELECT USERNAME as "Very Long Column Header That Should Test Word Wrap",
       PASSWORD as "Another Extremely Long Column Header For Testing Display",
       EMAIL as "Yet Another Long Column Header To Verify Word Wrap Functionality",
       CREATED_ON as "Creation Timestamp With Long Header",
       LAST_LOGIN as "Last Login Time With Extended Header Name"
FROM ACCOUNT_TEST
WHERE USERNAME LIKE '%long%'
   OR EMAIL LIKE '%long%'
   OR PASSWORD LIKE '%long%'
ORDER BY CREATED_ON DESC;

-- Create table with varied column widths for word wrap testing
DROP TABLE IF EXISTS WORDWRAP_TEST;
CREATE TABLE WORDWRAP_TEST (
    ID INT PRIMARY KEY AUTO_INCREMENT,
    SHORT_COL VARCHAR(10),
    MEDIUM_COL VARCHAR(50),
    LONG_COL VARCHAR(200),
    EXTRA_LONG_COL TEXT
);

-- Insert test data with different lengths for each column
INSERT INTO WORDWRAP_TEST (SHORT_COL, MEDIUM_COL, LONG_COL, EXTRA_LONG_COL) VALUES
('ABC', 'Medium length text content here', 'This is a long column with much more text content that should definitely cause word wrapping issues when displayed in a narrow terminal or window', 'This is an extremely long text field that contains a lot of content and should definitely test the word wrapping functionality thoroughly. It has multiple sentences and should span across several lines when word wrapped. This text is intentionally verbose to test how the display handles very long content in table cells.'),
('XY', 'Another medium text', 'Another long text entry that should also cause word wrapping when the column width is constrained by the terminal or display window size', 'Another extremely long text entry for comprehensive testing of word wrap functionality. This text should also span multiple lines and test how the cursor detection works when navigating through wrapped content in different columns.'),
('DEFGH', 'Short text', 'Medium length text that might or might not wrap depending on the display width and column sizing algorithm used by the plugin', 'Final long text entry to test word wrapping behavior with varied content lengths across all columns in the same row.');

-- Test queries for word wrap cursor detection
SELECT * FROM WORDWRAP_TEST;
SELECT SHORT_COL, MEDIUM_COL FROM WORDWRAP_TEST;
SELECT LONG_COL, EXTRA_LONG_COL FROM WORDWRAP_TEST;
SELECT ID, SHORT_COL, LONG_COL FROM WORDWRAP_TEST;


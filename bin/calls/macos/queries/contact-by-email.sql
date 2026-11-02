-- The contact with this email address, whatever its case.
SELECT person.ZFIRSTNAME AS firstName, person.ZLASTNAME AS lastName
FROM ZABCDEMAILADDRESS email
JOIN ZABCDRECORD person ON person.Z_PK = email.ZOWNER
WHERE lower(email.ZADDRESS) = lower($email);

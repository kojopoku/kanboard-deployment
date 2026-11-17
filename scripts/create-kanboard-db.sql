-- Kanboard database setup for MariaDB 10.11
-- Run as: sudo mariadb < scripts/create-kanboard-db.sql
-- Replace CHANGE_ME with a strong password before running

CREATE DATABASE kanboard CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'kanboard'@'localhost' IDENTIFIED BY 'CHANGE_ME';
GRANT ALL PRIVILEGES ON kanboard.* TO 'kanboard'@'localhost';

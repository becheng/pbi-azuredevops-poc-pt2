CREATE TABLE Customer (
    customerID int IDENTITY(1,1) NOT NULL,
    customerName varchar(255) NOT NULL
);

SET IDENTITY_INSERT dbo.Customer ON;  

INSERT dbo.Customer (customerID, customerName) VALUES (1, 'Captain America');
INSERT dbo.Customer (customerID, customerName) VALUES (2, 'Black Widow');
INSERT dbo.Customer (customerID, customerName) VALUES (3, 'Black Panther');
INSERT dbo.Customer (customerID, customerName) VALUES (4, 'Shuri');
INSERT dbo.Customer (customerID, customerName) VALUES (5, 'Okoye');
INSERT dbo.Customer (customerID, customerName) VALUES (6, 'Ant-Man');
INSERT dbo.Customer (customerID, customerName) VALUES (7, 'Doctor Strange');
INSERT dbo.Customer (customerID, customerName) VALUES (8, 'Hawkeye');
INSERT dbo.Customer (customerID, customerName) VALUES (9, 'Falcon');
INSERT dbo.Customer (customerID, customerName) VALUES (10, 'Red Skull');

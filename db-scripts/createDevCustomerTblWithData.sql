CREATE TABLE Customer (
    customerID int IDENTITY(1,1) NOT NULL,
    customerName varchar(255) NOT NULL
);

SET IDENTITY_INSERT dbo.Customer ON;  

INSERT dbo.Customer (customerID, customerName) VALUES (1, 'customer A');
INSERT dbo.Customer (customerID, customerName) VALUES (2, 'customer B');
INSERT dbo.Customer (customerID, customerName) VALUES (3, 'customer C');
INSERT dbo.Customer (customerID, customerName) VALUES (4, 'customer D');
INSERT dbo.Customer (customerID, customerName) VALUES (5, 'customer E');
INSERT dbo.Customer (customerID, customerName) VALUES (6, 'customer F');
INSERT dbo.Customer (customerID, customerName) VALUES (7, 'customer G');
INSERT dbo.Customer (customerID, customerName) VALUES (8, 'customer H');
INSERT dbo.Customer (customerID, customerName) VALUES (9, 'customer I');
INSERT dbo.Customer (customerID, customerName) VALUES (10, 'customer J');

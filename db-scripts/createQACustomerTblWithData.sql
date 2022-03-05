CREATE TABLE Customer (
    customerID int IDENTITY(1,1) NOT NULL,
    customerName varchar(255) NOT NULL
);

SET IDENTITY_INSERT dbo.Customer ON;  

INSERT dbo.Customer (customerID, customerName) VALUES (1, 'Mickey Mouse');
INSERT dbo.Customer (customerID, customerName) VALUES (2, 'Wendy');
INSERT dbo.Customer (customerID, customerName) VALUES (3, 'Evil Queen');
INSERT dbo.Customer (customerID, customerName) VALUES (4, 'Eeyore');
INSERT dbo.Customer (customerID, customerName) VALUES (5, 'Horace Horsecollar');
INSERT dbo.Customer (customerID, customerName) VALUES (6, 'Nala');
INSERT dbo.Customer (customerID, customerName) VALUES (7, 'Gus Gus');
INSERT dbo.Customer (customerID, customerName) VALUES (8, 'Flit');
INSERT dbo.Customer (customerID, customerName) VALUES (9, 'Fauna');
INSERT dbo.Customer (customerID, customerName) VALUES (10, 'Sir Hiss');

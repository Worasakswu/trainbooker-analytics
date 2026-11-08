CREATE TABLE Lines (
    LineID INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    LineName VARCHAR(50) NOT NULL
);

CREATE TABLE Stations (
    StationID INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    StationName VARCHAR(100) NOT NULL,
    LineID INT NOT NULL,
    StationOrder INT NOT NULL,
    Locations VARCHAR(100),
    CONSTRAINT fk_station_line
        FOREIGN KEY (LineID) REFERENCES Lines(LineID)
        ON DELETE CASCADE
);

CREATE TABLE Trains (
    TrainID INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    TrainName VARCHAR(100) NOT NULL,
    TrainType VARCHAR(20),
    TotalSeats INT CHECK (TotalSeats > 0)
);

CREATE TABLE Users (
    UserID INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    Username VARCHAR(50) UNIQUE NOT NULL,
    Password VARCHAR(50) NOT NULL,
    FullName VARCHAR(100),
    Email VARCHAR(100),
    Phone VARCHAR(15)
);

CREATE TABLE Schedules (
    ScheduleID INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    TrainID INT NOT NULL,
    OriginStationID INT NOT NULL,
    DestinationStationID INT NOT NULL,
    DepartureTime TIMESTAMP NOT NULL,
    ArrivalTime TIMESTAMP NOT NULL,
    Price DECIMAL(10,2),

    CONSTRAINT fk_schedule_train
        FOREIGN KEY (TrainID) REFERENCES Trains(TrainID),

    CONSTRAINT fk_schedule_origin
        FOREIGN KEY (OriginStationID) REFERENCES Stations(StationID),

    CONSTRAINT fk_schedule_destination
        FOREIGN KEY (DestinationStationID) REFERENCES Stations(StationID)
);

CREATE TABLE Bookings (
    BookingID INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    UserID INT NOT NULL,
    ScheduleID INT NOT NULL,
    Status VARCHAR(50),

    CONSTRAINT fk_booking_user
        FOREIGN KEY (UserID) REFERENCES Users(UserID)
        ON DELETE CASCADE,

    CONSTRAINT fk_booking_schedule
        FOREIGN KEY (ScheduleID) REFERENCES Schedules(ScheduleID)
        ON DELETE CASCADE
);

CREATE TABLE Tickets (
    TicketID INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    BookingID INT NOT NULL,
    SeatNumber VARCHAR(10),
    PassengerName VARCHAR(100),

    CONSTRAINT fk_ticket_booking
        FOREIGN KEY (BookingID) REFERENCES Bookings(BookingID)
        ON DELETE CASCADE
);

CREATE TABLE Payments (
    PaymentID INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    BookingID INT NOT NULL,
    Amount DECIMAL(10,2),
    PaymentMethod VARCHAR(50),
    PaymentDate TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_payment_booking
        FOREIGN KEY (BookingID) REFERENCES Bookings(BookingID)
        ON DELETE CASCADE
);
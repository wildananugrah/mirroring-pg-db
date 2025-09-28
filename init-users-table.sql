-- Create users table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    age INTEGER CHECK (age >= 0),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_active ON users(is_active);

-- Insert sample data
INSERT INTO users (username, email, first_name, last_name, age, is_active) VALUES
    ('john_doe', 'john.doe@example.com', 'John', 'Doe', 30, true),
    ('jane_smith', 'jane.smith@example.com', 'Jane', 'Smith', 28, true),
    ('bob_johnson', 'bob.johnson@example.com', 'Bob', 'Johnson', 35, true),
    ('alice_williams', 'alice.williams@example.com', 'Alice', 'Williams', 25, true),
    ('charlie_brown', 'charlie.brown@example.com', 'Charlie', 'Brown', 42, true),
    ('diana_davis', 'diana.davis@example.com', 'Diana', 'Davis', 31, true),
    ('edward_miller', 'edward.miller@example.com', 'Edward', 'Miller', 29, false),
    ('fiona_wilson', 'fiona.wilson@example.com', 'Fiona', 'Wilson', 33, true),
    ('george_moore', 'george.moore@example.com', 'George', 'Moore', 45, true),
    ('helen_taylor', 'helen.taylor@example.com', 'Helen', 'Taylor', 27, true),
    ('ivan_anderson', 'ivan.anderson@example.com', 'Ivan', 'Anderson', 38, false),
    ('julia_thomas', 'julia.thomas@example.com', 'Julia', 'Thomas', 26, true),
    ('kevin_jackson', 'kevin.jackson@example.com', 'Kevin', 'Jackson', 34, true),
    ('laura_white', 'laura.white@example.com', 'Laura', 'White', 29, true),
    ('michael_harris', 'michael.harris@example.com', 'Michael', 'Harris', 41, true),
    ('nancy_martin', 'nancy.martin@example.com', 'Nancy', 'Martin', 32, true),
    ('oscar_thompson', 'oscar.thompson@example.com', 'Oscar', 'Thompson', 36, false),
    ('paula_garcia', 'paula.garcia@example.com', 'Paula', 'Garcia', 28, true),
    ('quincy_martinez', 'quincy.martinez@example.com', 'Quincy', 'Martinez', 39, true),
    ('rachel_robinson', 'rachel.robinson@example.com', 'Rachel', 'Robinson', 24, true);

-- Create a function to update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create trigger to automatically update updated_at
CREATE TRIGGER update_users_updated_at BEFORE UPDATE
    ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Display the inserted data
SELECT COUNT(*) as total_users FROM users;
SELECT * FROM users ORDER BY id LIMIT 10;
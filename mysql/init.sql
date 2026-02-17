-- ============================================================
-- MedAssist Database - Schema and Sample Data
-- Plateforme de teleconsultation medicale
-- ============================================================

CREATE DATABASE IF NOT EXISTS medassist;
USE medassist;

-- ------------------------------------------------------------
-- Medecins
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS doctors (
    id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    specialty VARCHAR(100) NOT NULL,
    license_number VARCHAR(50) NOT NULL UNIQUE,
    available BOOLEAN DEFAULT TRUE,
    consultation_price DECIMAL(10, 2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
-- Patients
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS patients (
    id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL,
    date_of_birth DATE,
    social_security VARCHAR(15),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
-- Consultations (rendez-vous)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS consultations (
    id INT AUTO_INCREMENT PRIMARY KEY,
    patient_id INT NOT NULL,
    doctor_id INT NOT NULL,
    scheduled_at DATETIME NOT NULL,
    duration_minutes INT DEFAULT 30,
    status ENUM('scheduled', 'in_progress', 'completed', 'cancelled', 'no_show') DEFAULT 'scheduled',
    consultation_type ENUM('general', 'follow_up', 'urgent', 'specialist') DEFAULT 'general',
    notes TEXT,
    total_price DECIMAL(10, 2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES patients(id),
    FOREIGN KEY (doctor_id) REFERENCES doctors(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
-- Paiements
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS payments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    consultation_id INT NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    status ENUM('pending', 'completed', 'failed', 'refunded') DEFAULT 'pending',
    payment_method ENUM('card', 'mutual', 'transfer') DEFAULT 'card',
    transaction_id VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (consultation_id) REFERENCES consultations(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
-- Notifications
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notifications (
    id INT AUTO_INCREMENT PRIMARY KEY,
    patient_id INT,
    consultation_id INT,
    type ENUM('email', 'sms', 'push') DEFAULT 'email',
    status ENUM('pending', 'sent', 'failed') DEFAULT 'pending',
    message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (patient_id) REFERENCES patients(id),
    FOREIGN KEY (consultation_id) REFERENCES consultations(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ------------------------------------------------------------
-- Sample Doctors
-- ------------------------------------------------------------
INSERT INTO doctors (first_name, last_name, specialty, license_number, available, consultation_price) VALUES
    ('Sophie', 'Martin', 'Medecine generale', 'MED-2024-001', TRUE, 25.00),
    ('Pierre', 'Dubois', 'Dermatologie', 'MED-2024-002', TRUE, 50.00),
    ('Claire', 'Bernard', 'Pediatrie', 'MED-2024-003', TRUE, 35.00),
    ('Jean', 'Moreau', 'Cardiologie', 'MED-2024-004', TRUE, 60.00),
    ('Marie', 'Petit', 'Psychiatrie', 'MED-2024-005', TRUE, 55.00),
    ('Luc', 'Robert', 'Medecine generale', 'MED-2024-006', TRUE, 25.00),
    ('Anne', 'Richard', 'Gynecologie', 'MED-2024-007', TRUE, 45.00),
    ('Thomas', 'Durand', 'Ophtalmologie', 'MED-2024-008', FALSE, 40.00),
    ('Julie', 'Leroy', 'Medecine generale', 'MED-2024-009', TRUE, 25.00),
    ('Nicolas', 'Simon', 'ORL', 'MED-2024-010', TRUE, 45.00);

-- ------------------------------------------------------------
-- Sample Patients
-- ------------------------------------------------------------
INSERT INTO patients (first_name, last_name, email, date_of_birth, social_security) VALUES
    ('Alice', 'Dupont', 'alice.dupont@email.com', '1990-03-15', '290037512345'),
    ('Bob', 'Lambert', 'bob.lambert@email.com', '1985-07-22', '185077823456'),
    ('Camille', 'Garcia', 'camille.garcia@email.com', '1992-11-08', '292117634567'),
    ('David', 'Roux', 'david.roux@email.com', '1978-01-30', '178017845678'),
    ('Emma', 'Fournier', 'emma.fournier@email.com', '2000-06-12', '200067856789'),
    ('Francois', 'Girard', 'francois.girard@email.com', '1965-09-05', '165097867890'),
    ('Helene', 'Bonnet', 'helene.bonnet@email.com', '1988-12-20', '288127878901'),
    ('Ibrahim', 'Ndiaye', 'ibrahim.ndiaye@email.com', '1995-04-18', '195047889012'),
    ('Julie', 'Mercier', 'julie.mercier@email.com', '2002-08-25', '202087890123'),
    ('Kevin', 'Blanc', 'kevin.blanc@email.com', '1970-02-14', '170027801234');

-- ------------------------------------------------------------
-- Sample Consultations
-- ------------------------------------------------------------
INSERT INTO consultations (patient_id, doctor_id, scheduled_at, duration_minutes, status, consultation_type, total_price) VALUES
    (1, 1, '2025-01-15 09:00:00', 30, 'completed', 'general', 25.00),
    (2, 2, '2025-01-15 10:00:00', 30, 'completed', 'specialist', 50.00),
    (3, 3, '2025-01-15 11:00:00', 30, 'completed', 'general', 35.00),
    (4, 4, '2025-01-15 14:00:00', 45, 'completed', 'urgent', 60.00),
    (5, 5, '2025-01-16 09:30:00', 60, 'completed', 'follow_up', 55.00),
    (1, 1, '2025-01-16 10:00:00', 30, 'cancelled', 'general', 25.00),
    (6, 6, '2025-01-16 11:00:00', 30, 'completed', 'general', 25.00),
    (7, 7, '2025-01-17 09:00:00', 30, 'scheduled', 'specialist', 45.00),
    (8, 1, '2025-01-17 10:30:00', 30, 'scheduled', 'general', 25.00),
    (9, 3, '2025-01-17 14:00:00', 30, 'scheduled', 'general', 35.00),
    (10, 4, '2025-01-17 15:00:00', 45, 'scheduled', 'urgent', 60.00),
    (2, 5, '2025-01-18 09:00:00', 60, 'scheduled', 'follow_up', 55.00);

-- ------------------------------------------------------------
-- Sample Payments
-- ------------------------------------------------------------
INSERT INTO payments (consultation_id, amount, status, payment_method, transaction_id) VALUES
    (1, 25.00, 'completed', 'card', 'txn_100001'),
    (2, 50.00, 'completed', 'card', 'txn_100002'),
    (3, 35.00, 'completed', 'mutual', 'txn_100003'),
    (4, 60.00, 'completed', 'card', 'txn_100004'),
    (5, 55.00, 'completed', 'transfer', 'txn_100005'),
    (7, 25.00, 'completed', 'card', 'txn_100006');

-- ------------------------------------------------------------
-- Sample Notifications
-- ------------------------------------------------------------
INSERT INTO notifications (patient_id, consultation_id, type, status, message) VALUES
    (1, 1, 'email', 'sent', 'Votre consultation avec Dr. Martin est confirmee pour le 15/01 a 9h.'),
    (2, 2, 'email', 'sent', 'Votre consultation avec Dr. Dubois est confirmee pour le 15/01 a 10h.'),
    (3, 3, 'sms', 'sent', 'Rappel : consultation Dr. Bernard demain a 11h.'),
    (4, 4, 'email', 'sent', 'Votre consultation urgente avec Dr. Moreau est confirmee.'),
    (1, 6, 'email', 'sent', 'Votre consultation du 16/01 a ete annulee.'),
    (7, 8, 'email', 'pending', 'Rappel : consultation Dr. Richard le 17/01 a 9h.'),
    (8, 9, 'sms', 'pending', 'Rappel : consultation Dr. Martin le 17/01 a 10h30.');

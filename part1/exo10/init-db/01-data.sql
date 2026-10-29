-- Création de la table
CREATE TABLE IF NOT EXISTS notes (
    id SERIAL PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    content VARCHAR(5000),
    category VARCHAR(50),
    priority VARCHAR(20) DEFAULT 'MEDIUM',
    attachment_path VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Données de démonstration
INSERT INTO notes (title, content, category, priority, created_at, updated_at)
VALUES 
    ('Bienvenue', 'Ceci est votre première note.', 'PERSONAL', 'MEDIUM', NOW(), NOW()),
    ('Liste de courses', 'Pain, lait, oeufs', 'PERSONAL', 'LOW', NOW(), NOW()),
    ('Réunion projet', 'Préparer la présentation Docker', 'WORK', 'HIGH', NOW(), NOW())
ON CONFLICT DO NOTHING;

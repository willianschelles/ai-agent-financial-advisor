-- Render PostgreSQL Setup Script for AI Agent Financial Advisor
-- This script will be run during the database initialization process

-- Enable the vector extension for pgvector
CREATE EXTENSION IF NOT EXISTS vector;

-- Create the schema if it doesn't exist
-- CREATE SCHEMA IF NOT EXISTS public;

-- Grant privileges
-- GRANT ALL ON SCHEMA public TO public;

-- Set timezone to UTC
SET timezone = 'UTC';

-- Create custom functions/procedures if needed
-- Example: Create a function to perform a cosine similarity search
CREATE OR REPLACE FUNCTION cosine_similarity(a vector, b vector)
RETURNS float AS $$
  SELECT 1 - (a <=> b);
$$ LANGUAGE SQL IMMUTABLE STRICT PARALLEL SAFE;

-- Create index function if using custom metrics
CREATE OR REPLACE FUNCTION l2_distance(a vector, b vector)
RETURNS float AS $$
  SELECT a <-> b;
$$ LANGUAGE SQL IMMUTABLE STRICT PARALLEL SAFE;

-- Add any other database setup tasks below
-- This might include:
-- - Creating roles
-- - Setting up schemas
-- - Creating database extensions
-- - Setting configuration parameters

-- Example: Set statement timeout to 30 seconds
ALTER DATABASE CURRENT SET statement_timeout = '30s';

-- Example: Enable row-level security
-- ALTER DATABASE CURRENT SET row_security = on;

-- Log completion
DO $$
BEGIN
  RAISE NOTICE 'Database setup completed successfully';
END $$;

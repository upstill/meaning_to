-- Create the categories table
CREATE TABLE IF NOT EXISTS "categories" (
    "id" SERIAL PRIMARY KEY,
    "headline" TEXT NOT NULL,
    "owner_id" UUID NOT NULL,
    "created_at" TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    "updated_at" TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS on the categories table
ALTER TABLE "categories" ENABLE ROW LEVEL SECURITY;

-- Create policies for categories table
-- Policy for reading categories
CREATE POLICY "Users can read their own categories" ON "categories"
    FOR SELECT
    USING (
        auth.uid() = owner_id OR 
        (auth.uid() IS NULL AND owner_id = '35ed4d18-84b4-481d-96f4-1405c2f2f1ae')
    );

-- Policy for inserting categories
CREATE POLICY "Users can insert their own categories" ON "categories"
    FOR INSERT
    WITH CHECK (
        auth.uid() = owner_id OR 
        (auth.uid() IS NULL AND owner_id = '35ed4d18-84b4-481d-96f4-1405c2f2f1ae')
    );

-- Policy for updating categories
CREATE POLICY "Users can update their own categories" ON "categories"
    FOR UPDATE
    USING (
        auth.uid() = owner_id OR 
        (auth.uid() IS NULL AND owner_id = '35ed4d18-84b4-481d-96f4-1405c2f2f1ae')
    )
    WITH CHECK (
        auth.uid() = owner_id OR 
        (auth.uid() IS NULL AND owner_id = '35ed4d18-84b4-481d-96f4-1405c2f2f1ae')
    );

-- Policy for deleting categories
CREATE POLICY "Users can delete their own categories" ON "categories"
    FOR DELETE
    USING (
        auth.uid() = owner_id OR 
        (auth.uid() IS NULL AND owner_id = '35ed4d18-84b4-481d-96f4-1405c2f2f1ae')
    );

-- Insert some default categories for the guest user
INSERT INTO "categories" ("headline", "owner_id") VALUES
    ('Work', '35ed4d18-84b4-481d-96f4-1405c2f2f1ae'),
    ('Personal', '35ed4d18-84b4-481d-96f4-1405c2f2f1ae'),
    ('Health', '35ed4d18-84b4-481d-96f4-1405c2f2f1ae'),
    ('Learning', '35ed4d18-84b4-481d-96f4-1405c2f2f1ae')
ON CONFLICT DO NOTHING;

-- Verify the table was created
SELECT * FROM "categories" WHERE "owner_id" = '35ed4d18-84b4-481d-96f4-1405c2f2f1ae'; 
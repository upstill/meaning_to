-- Clean up conflicting RLS policies and ensure proper guest access
-- This will remove overly permissive policies and keep only the correct ones

-- First, drop all existing policies to start clean
DROP POLICY IF EXISTS "Users can create their own categories" ON "Categories";
DROP POLICY IF EXISTS "Users can delete their own categories" ON "Categories";
DROP POLICY IF EXISTS "Users can insert their own categories" ON "Categories";
DROP POLICY IF EXISTS "Users can read their own categories" ON "Categories";
DROP POLICY IF EXISTS "Users can update their own categories" ON "Categories";
DROP POLICY IF EXISTS "Users can view their own categories" ON "Categories";
DROP POLICY IF EXISTS "category_access" ON "Categories";

DROP POLICY IF EXISTS "Allow users to delete their own Tasks" ON "Tasks";
DROP POLICY IF EXISTS "Allow users to modify their own tasks" ON "Tasks";
DROP POLICY IF EXISTS "Allow users to update their own categories" ON "Tasks";
DROP POLICY IF EXISTS "Enable insert for users based on owner_id" ON "Tasks";
DROP POLICY IF EXISTS "Enable read access for all users" ON "Tasks";
DROP POLICY IF EXISTS "Users can delete their own tasks" ON "Tasks";
DROP POLICY IF EXISTS "Users can insert their own tasks" ON "Tasks";
DROP POLICY IF EXISTS "Users can read their own tasks" ON "Tasks";
DROP POLICY IF EXISTS "Users can update their own tasks" ON "Tasks";

-- Now create clean, correct policies for Categories
CREATE POLICY "Users can read their own categories" ON "Categories"
    FOR SELECT
    USING (
        auth.uid() = owner_id OR 
        (auth.uid() IS NULL AND owner_id = '35ed4d18-84b4-481d-96f4-1405c2f2f1ae')
    );

CREATE POLICY "Users can insert their own categories" ON "Categories"
    FOR INSERT
    WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "Users can update their own categories" ON "Categories"
    FOR UPDATE
    USING (auth.uid() = owner_id)
    WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "Users can delete their own categories" ON "Categories"
    FOR DELETE
    USING (auth.uid() = owner_id);

-- Create clean, correct policies for Tasks
CREATE POLICY "Users can read their own tasks" ON "Tasks"
    FOR SELECT
    USING (
        auth.uid() = owner_id OR 
        (auth.uid() IS NULL AND owner_id = '35ed4d18-84b4-481d-96f4-1405c2f2f1ae')
    );

CREATE POLICY "Users can insert their own tasks" ON "Tasks"
    FOR INSERT
    WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "Users can update their own tasks" ON "Tasks"
    FOR UPDATE
    USING (auth.uid() = owner_id)
    WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "Users can delete their own tasks" ON "Tasks"
    FOR DELETE
    USING (auth.uid() = owner_id);

-- Verify the new policies
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies 
WHERE tablename IN ('Tasks', 'Categories')
ORDER BY tablename, policyname; 
-- Check current RLS policies on Tasks table
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
WHERE tablename = 'Tasks';

-- Check if RLS is enabled on Tasks table
SELECT 
    schemaname,
    tablename,
    rowsecurity
FROM pg_tables 
WHERE tablename = 'Tasks';

-- Drop existing policies if they're too restrictive
DROP POLICY IF EXISTS "Users can update their own tasks" ON "Tasks";
DROP POLICY IF EXISTS "Users can read their own tasks" ON "Tasks";
DROP POLICY IF EXISTS "Users can insert their own tasks" ON "Tasks";
DROP POLICY IF EXISTS "Users can delete their own tasks" ON "Tasks";

-- Create new, more permissive policies that handle guest users
-- Policy for reading tasks
CREATE POLICY "Users can read their own tasks" ON "Tasks"
    FOR SELECT
    USING (
        auth.uid() = owner_id OR 
        (auth.uid() IS NULL AND owner_id = '35ed4d18-84b4-481d-96f4-1405c2f2f1ae')
    );

-- Policy for inserting tasks
CREATE POLICY "Users can insert their own tasks" ON "Tasks"
    FOR INSERT
    WITH CHECK (
        auth.uid() = owner_id OR 
        (auth.uid() IS NULL AND owner_id = '35ed4d18-84b4-481d-96f4-1405c2f2f1ae')
    );

-- Policy for updating tasks
CREATE POLICY "Users can update their own tasks" ON "Tasks"
    FOR UPDATE
    USING (
        auth.uid() = owner_id OR 
        (auth.uid() IS NULL AND owner_id = '35ed4d18-84b4-481d-96f4-1405c2f2f1ae')
    )
    WITH CHECK (
        auth.uid() = owner_id OR 
        (auth.uid() IS NULL AND owner_id = '35ed4d18-84b4-481d-96f4-1405c2f2f1ae')
    );

-- Policy for deleting tasks
CREATE POLICY "Users can delete their own tasks" ON "Tasks"
    FOR DELETE
    USING (
        auth.uid() = owner_id OR 
        (auth.uid() IS NULL AND owner_id = '35ed4d18-84b4-481d-96f4-1405c2f2f1ae')
    );

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
WHERE tablename = 'Tasks'; 
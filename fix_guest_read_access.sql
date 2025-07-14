-- Fix guest user access: Allow reading guest categories but not modifying them
-- This allows unauthenticated users to see guest categories but not modify data

-- Drop existing policies for Tasks table
DROP POLICY IF EXISTS "Users can update their own tasks" ON "Tasks";
DROP POLICY IF EXISTS "Users can read their own tasks" ON "Tasks";
DROP POLICY IF EXISTS "Users can insert their own tasks" ON "Tasks";
DROP POLICY IF EXISTS "Users can delete their own tasks" ON "Tasks";

-- Create new policies for Tasks
-- Policy for reading tasks - authenticated users can read their own, guests can read guest tasks
CREATE POLICY "Users can read their own tasks" ON "Tasks"
    FOR SELECT
    USING (
        auth.uid() = owner_id OR 
        (auth.uid() IS NULL AND owner_id = '35ed4d18-84b4-481d-96f4-1405c2f2f1ae')
    );

-- Policy for inserting tasks - only authenticated users
CREATE POLICY "Users can insert their own tasks" ON "Tasks"
    FOR INSERT
    WITH CHECK (auth.uid() = owner_id);

-- Policy for updating tasks - only authenticated users
CREATE POLICY "Users can update their own tasks" ON "Tasks"
    FOR UPDATE
    USING (auth.uid() = owner_id)
    WITH CHECK (auth.uid() = owner_id);

-- Policy for deleting tasks - only authenticated users
CREATE POLICY "Users can delete their own tasks" ON "Tasks"
    FOR DELETE
    USING (auth.uid() = owner_id);

-- Drop existing policies for Categories table
DROP POLICY IF EXISTS "Users can update their own categories" ON "Categories";
DROP POLICY IF EXISTS "Users can read their own categories" ON "Categories";
DROP POLICY IF EXISTS "Users can insert their own categories" ON "Categories";
DROP POLICY IF EXISTS "Users can delete their own categories" ON "Categories";

-- Create new policies for Categories
-- Policy for reading categories - authenticated users can read their own, guests can read guest categories
CREATE POLICY "Users can read their own categories" ON "Categories"
    FOR SELECT
    USING (
        auth.uid() = owner_id OR 
        (auth.uid() IS NULL AND owner_id = '35ed4d18-84b4-481d-96f4-1405c2f2f1ae')
    );

-- Policy for inserting categories - only authenticated users
CREATE POLICY "Users can insert their own categories" ON "Categories"
    FOR INSERT
    WITH CHECK (auth.uid() = owner_id);

-- Policy for updating categories - only authenticated users
CREATE POLICY "Users can update their own categories" ON "Categories"
    FOR UPDATE
    USING (auth.uid() = owner_id)
    WITH CHECK (auth.uid() = owner_id);

-- Policy for deleting categories - only authenticated users
CREATE POLICY "Users can delete their own categories" ON "Categories"
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
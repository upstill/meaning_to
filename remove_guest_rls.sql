-- Remove guest user fallbacks from RLS policies
-- This will require authentication for all operations

-- Drop existing policies for Tasks table
DROP POLICY IF EXISTS "Users can update their own tasks" ON "Tasks";
DROP POLICY IF EXISTS "Users can read their own tasks" ON "Tasks";
DROP POLICY IF EXISTS "Users can insert their own tasks" ON "Tasks";
DROP POLICY IF EXISTS "Users can delete their own tasks" ON "Tasks";

-- Create new policies for Tasks that require authentication
-- Policy for reading tasks
CREATE POLICY "Users can read their own tasks" ON "Tasks"
    FOR SELECT
    USING (auth.uid() = owner_id);

-- Policy for inserting tasks
CREATE POLICY "Users can insert their own tasks" ON "Tasks"
    FOR INSERT
    WITH CHECK (auth.uid() = owner_id);

-- Policy for updating tasks
CREATE POLICY "Users can update their own tasks" ON "Tasks"
    FOR UPDATE
    USING (auth.uid() = owner_id)
    WITH CHECK (auth.uid() = owner_id);

-- Policy for deleting tasks
CREATE POLICY "Users can delete their own tasks" ON "Tasks"
    FOR DELETE
    USING (auth.uid() = owner_id);

-- Drop existing policies for Categories table
DROP POLICY IF EXISTS "Users can update their own categories" ON "Categories";
DROP POLICY IF EXISTS "Users can read their own categories" ON "Categories";
DROP POLICY IF EXISTS "Users can insert their own categories" ON "Categories";
DROP POLICY IF EXISTS "Users can delete their own categories" ON "Categories";

-- Create new policies for Categories that require authentication
-- Policy for reading categories
CREATE POLICY "Users can read their own categories" ON "Categories"
    FOR SELECT
    USING (auth.uid() = owner_id);

-- Policy for inserting categories
CREATE POLICY "Users can insert their own categories" ON "Categories"
    FOR INSERT
    WITH CHECK (auth.uid() = owner_id);

-- Policy for updating categories
CREATE POLICY "Users can update their own categories" ON "Categories"
    FOR UPDATE
    USING (auth.uid() = owner_id)
    WITH CHECK (auth.uid() = owner_id);

-- Policy for deleting categories
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
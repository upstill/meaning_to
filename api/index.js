// Vercel serverless function for handling Supabase operations
import { createClient } from '@supabase/supabase-js'

const supabaseUrl = process.env.SUPABASE_URL
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY

console.log('API: Initializing with URL:', supabaseUrl ? 'SET' : 'NOT SET')
console.log('API: Service key:', supabaseServiceKey ? 'SET' : 'NOT SET')

const supabase = createClient(supabaseUrl, supabaseServiceKey)

export default async function handler(req, res) {
  console.log('API: Request received:', req.method, req.url)
  console.log('API: Headers:', req.headers)
  console.log('API: Body:', req.body)

  // Enable CORS
  res.setHeader('Access-Control-Allow-Origin', '*')
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization')

  if (req.method === 'OPTIONS') {
    console.log('API: Handling OPTIONS request')
    res.status(200).end()
    return
  }

  try {
    const { action, data, userId } = req.body
    console.log('API: Action:', action)
    console.log('API: User ID:', userId)
    console.log('API: Data:', data)

    switch (action) {
      case 'getTask':
        const { taskId } = data
        console.log('API: Getting task:', taskId)
        const { data: task, error: taskError } = await supabase
          .from('Tasks')
          .select('*')
          .eq('id', taskId)
          .eq('owner_id', userId)
          .single()
        
        if (taskError) {
          console.log('API: Task error:', taskError)
          if (taskError.code === 'PGRST116') {
            // Task not found
            res.json({ success: true, data: null })
          } else {
            throw taskError
          }
        } else {
          console.log('API: Task found:', task)
          res.json({ success: true, data: [task] })
        }
        break

      case 'updateTask':
        const { taskId: updateTaskId, updates } = data
        console.log('API: Updating task:', updateTaskId, updates)
        const { data: result, error } = await supabase
          .from('Tasks')
          .update(updates)
          .eq('id', updateTaskId)
          .eq('owner_id', userId)
          .select()
        
        if (error) throw error
        console.log('API: Update result:', result)
        res.json({ success: true, data: result })
        break

      case 'getTasks':
        console.log('API: Getting tasks for user:', userId)
        const { data: tasks, error: tasksError } = await supabase
          .from('Tasks')
          .select('*')
          .eq('owner_id', userId)
          .order('created_at', { ascending: false })
        
        if (tasksError) throw tasksError
        console.log('API: Found tasks:', tasks.length)
        res.json({ success: true, data: tasks })
        break

      case 'getTasksByCategoryAndUser':
        const { categoryId } = data
        console.log('API: Getting tasks for category:', categoryId, 'user:', userId)
        const { data: categoryTasks, error: categoryTasksError } = await supabase
          .from('Tasks')
          .select('*')
          .eq('category_id', categoryId)
          .eq('owner_id', userId)
          .order('created_at', { ascending: false })
        
        if (categoryTasksError) throw categoryTasksError
        console.log('API: Found category tasks:', categoryTasks.length)
        res.json({ success: true, data: categoryTasks })
        break

      case 'updateGuestTasks':
        const { guestUserId } = data
        console.log('API: Updating guest tasks for user:', guestUserId)
        const { data: guestTasksResult, error: guestTasksError } = await supabase
          .from('Tasks')
          .update({
            suggestible_at: null,
            deferral: null,
            finished: false,
          })
          .eq('owner_id', guestUserId)
        
        if (guestTasksError) throw guestTasksError
        console.log('API: Guest tasks updated')
        res.json({ success: true, data: guestTasksResult })
        break

      case 'getCategories':
        console.log('API: Getting categories for user:', userId)
        const { data: categories, error: categoriesError } = await supabase
          .from('Categories')
          .select('*')
          .eq('owner_id', userId)
          .order('created_at', { ascending: false })
        
        if (categoriesError) throw categoriesError
        console.log('API: Found categories:', categories.length)
        res.json({ success: true, data: categories })
        break

      case 'createTask':
        console.log('API: Creating task for user:', userId)
        const { data: newTask, error: createError } = await supabase
          .from('Tasks')
          .insert({ ...data, owner_id: userId })
          .select()
        
        if (createError) throw createError
        console.log('API: Task created:', newTask)
        res.json({ success: true, data: newTask })
        break

      case 'createCategory':
        console.log('API: Creating category for user:', userId)
        const { data: newCategory, error: createCategoryError } = await supabase
          .from('Categories')
          .insert({ ...data, owner_id: userId })
          .select()
        
        if (createCategoryError) throw createCategoryError
        console.log('API: Category created:', newCategory)
        res.json({ success: true, data: newCategory })
        break

      case 'deleteTask':
        console.log('API: Deleting task:', data.taskId, 'for user:', userId)
        const { data: deletedTask, error: deleteError } = await supabase
          .from('Tasks')
          .delete()
          .eq('id', data.taskId)
          .eq('owner_id', userId)
          .select()
        
        if (deleteError) throw deleteError
        console.log('API: Task deleted:', deletedTask)
        res.json({ success: true, data: deletedTask })
        break

      case 'deleteCategory':
        console.log('API: Deleting category:', data.categoryId, 'for user:', userId)
        const { data: deletedCategory, error: deleteCategoryError } = await supabase
          .from('Categories')
          .delete()
          .eq('id', data.categoryId)
          .eq('owner_id', userId)
          .select()
        
        if (deleteCategoryError) throw deleteCategoryError
        console.log('API: Category deleted:', deletedCategory)
        res.json({ success: true, data: deletedCategory })
        break

      default:
        console.log('API: Invalid action:', action)
        res.status(400).json({ error: 'Invalid action' })
    }
  } catch (error) {
    console.error('API Error:', error)
    res.status(500).json({ error: error.message })
  }
} 
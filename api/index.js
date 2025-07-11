// Vercel serverless function for handling Supabase operations
import { createClient } from '@supabase/supabase-js'

const supabaseUrl = process.env.SUPABASE_URL
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY

const supabase = createClient(supabaseUrl, supabaseServiceKey)

export default async function handler(req, res) {
  // Enable CORS
  res.setHeader('Access-Control-Allow-Origin', '*')
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization')

  if (req.method === 'OPTIONS') {
    res.status(200).end()
    return
  }

  try {
    const { action, data, userId } = req.body

    switch (action) {
      case 'getTask':
        const { taskId } = data
        const { data: task, error: taskError } = await supabase
          .from('Tasks')
          .select('*')
          .eq('id', taskId)
          .eq('owner_id', userId)
          .single()
        
        if (taskError) {
          if (taskError.code === 'PGRST116') {
            // Task not found
            res.json({ success: true, data: null })
          } else {
            throw taskError
          }
        } else {
          res.json({ success: true, data: [task] })
        }
        break

      case 'updateTask':
        const { taskId: updateTaskId, updates } = data
        const { data: result, error } = await supabase
          .from('Tasks')
          .update(updates)
          .eq('id', updateTaskId)
          .eq('owner_id', userId)
          .select()
        
        if (error) throw error
        res.json({ success: true, data: result })
        break

      case 'getTasks':
        const { data: tasks, error: tasksError } = await supabase
          .from('Tasks')
          .select('*')
          .eq('owner_id', userId)
          .order('created_at', { ascending: false })
        
        if (tasksError) throw tasksError
        res.json({ success: true, data: tasks })
        break

      case 'getCategories':
        const { data: categories, error: categoriesError } = await supabase
          .from('Categories')
          .select('*')
          .eq('owner_id', userId)
          .order('created_at', { ascending: false })
        
        if (categoriesError) throw categoriesError
        res.json({ success: true, data: categories })
        break

      case 'createTask':
        const { data: newTask, error: createError } = await supabase
          .from('Tasks')
          .insert({ ...data, owner_id: userId })
          .select()
        
        if (createError) throw createError
        res.json({ success: true, data: newTask })
        break

      case 'createCategory':
        const { data: newCategory, error: createCategoryError } = await supabase
          .from('Categories')
          .insert({ ...data, owner_id: userId })
          .select()
        
        if (createCategoryError) throw createCategoryError
        res.json({ success: true, data: newCategory })
        break

      case 'deleteTask':
        const { data: deletedTask, error: deleteError } = await supabase
          .from('Tasks')
          .delete()
          .eq('id', data.taskId)
          .eq('owner_id', userId)
          .select()
        
        if (deleteError) throw deleteError
        res.json({ success: true, data: deletedTask })
        break

      case 'deleteCategory':
        const { data: deletedCategory, error: deleteCategoryError } = await supabase
          .from('Categories')
          .delete()
          .eq('id', data.categoryId)
          .eq('owner_id', userId)
          .select()
        
        if (deleteCategoryError) throw deleteCategoryError
        res.json({ success: true, data: deletedCategory })
        break

      default:
        res.status(400).json({ error: 'Invalid action' })
    }
  } catch (error) {
    console.error('API Error:', error)
    res.status(500).json({ error: error.message })
  }
} 
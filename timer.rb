require 'sinatra'
require 'tilt/erubis'
require 'date'
require 'pry'

require_relative 'database_persistence'

configure(:development) do
  require 'sinatra/reloader'
  also_reload 'database_persistence.rb'
end

configure do
  enable :sessions
  set :erb, :escape_html => true   
end

def error_for_task_name(task_name)
  if !(1..30).cover?(task_name.size)
    'List name must be between 1 and 100 characters.'
  elsif @storage.all_tasks.any? { |task| task[:name] == task_name }
    'Task name must be unique.'
  end
end

def error_for_dates(date_start, date_end)
  return nil if date_start.empty? && date_end.empty?

  if date_start.empty? && date_end.size > 0
    'Use Start Date to search for a single date.'
  elsif invalid_date?(date_start)
    'Dates must be written in YYYY-MM-DD format.'
  elsif invalid_date?(date_end) && date_end.size > 0
    'Dates must be written in YYYY-MM-DD format.'
  elsif nonsequential_dates?(date_start, date_end)
    'End date must follow start date.'
  end
end

def nonsequential_dates?(date_start, date_end)
  return false if date_end.empty?
  
  y1, m1, d1 = date_start.split('-')
  y2, m2, d2 = date_end.split('-')
  
  first = Date.new(y1.to_i, m1.to_i, d1.to_i)
  second = Date.new(y2.to_i, m2.to_i, d2.to_i)
  
  first - second > 0
end

def invalid_date?(date_string)
  return true unless date_string.match?(/\d\d\d\d-\d\d-\d\d/)
  y, m, d = date_string.split('-')
  !Date.valid_date?(y.to_i, m.to_i, d.to_i)
end

before do
  @storage = DatabasePersistence.new(logger)
end

after do
  @storage.disconnect
end

get '/' do
  redirect '/timer'
end

get '/timer' do
  @tasks = @storage.all_tasks
  erb :home, layout: :layout
end

post '/start_time' do
  task_name = params[:task_name]

  if @storage.latest_task_completed?
    @storage.timer_start(task_name)
    session[:success] = "The timer has started for task: #{task_name}."
    redirect '/timer'
  else
    @tasks = @storage.all_tasks
    session[:error] = 'Please end the current task before starting another.'
    erb :home, layout: :layout
  end
end

post '/end_time' do
  current_task = @storage.current_task
  if current_task
    task_name = current_task[:task_name]
    @storage.timer_stop
    session[:success] = "Task #{task_name} has been completed."
    redirect '/timer'
  else
    session[:error] = 'Please begin a task before clicking End Time.'
    @tasks = @storage.all_tasks
    erb :home, layout: :layout
  end
end

post '/task/add' do
  task_name = params[:task_name]

  error = error_for_task_name(task_name)
  if error
    session[:error] = error
    @tasks = @storage.all_tasks
    erb :home, layout: :layout
  else
    @storage.add_task(task_name)
    session[:success] = "Task #{task_name} was added successfully."
    redirect '/timer'
  end
end

get '/timer/history' do
  @tasks_today = @storage.search_tasks('today')
  @current_date = @storage.format_date('today')
  @total_time_today = @storage.total_time_tasks_for_date('today') unless @tasks_today.empty?
  
  @tasks_last_seven_days = @storage.tasks_last_seven_days
  @total_time = @storage.total_time_last_seven_days unless @tasks_last_seven_days.empty?
  
  erb :history, layout: :layout
end

get '/timer/search' do
  @results = nil
  if !params.empty?
    task = params[:task]
    date_start = params[:date_start]
    date_end = params[:date_end]
  
    error = error_for_dates(date_start, date_end)

    if error
      session[:error] = error
    else
      @results = @storage.search_tasks(date_start, date_end, task)
    end
  end
  
  @tasks = @storage.all_tasks
  erb :search, layout: :layout
end

get '/timer/:date_stamp' do
  date_stamp = params[:date_stamp]
  redirect '/timer' unless @storage.data_for_date?(date_stamp)
  
  @formatted_date = @storage.format_date(date_stamp)
  @tasks = @storage.search_tasks(date_stamp)
  @total_time = @storage.total_time_tasks_for_date(date_stamp)
  
  erb :date, layout: :layout
end

post '/create_sample_data' do
  if @storage.exists_sample_data?
    session[:error] = 'Please delete old sample data before populating new sample data.'
  else
    @storage.populate_data
    session[:success] = 'New sample data has been populated.'
  end
  redirect '/timer'
end

post '/delete_all_data' do
  @storage.delete_data
  session[:success] = 'All data has been removed from the database.'
  redirect '/timer'
end

not_found do
  redirect '/timer'
end

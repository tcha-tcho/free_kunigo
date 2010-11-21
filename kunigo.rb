require 'rubygems'
require 'sinatra'
require 'erubis'
require 'sinatra/r18n'
require 'mongo_mapper'

require 'digest/sha1'
require 'bcrypt'

require 'pony'

helpers do
  include Rack::Utils
  alias_method :h, :escape_html

  #THIS MUST BE CHANGED TO LET KUNIGO SEND EMAILS!PLEASE USE A SMTP SERVER AS DESCRIBED ABOVE
  def send_mail(email,subject,body)
    Pony.mail(:to => email,
    :from => t.email.adress,
    :subject => subject,
    :body => body,
    :content_type => 'text/html',
    :charset => 'utf-8',
    :via => :smtp, :smtp => {
      :host       => 'smtp.kunigo.com.br',
      :port       => '587',
      :user       => 'kunigo@kunigo.com.br',
      :password   => 'PASSWORD',
      :auth       => :plain,
      :domain     => "localhost.localdomain"
    })
  end
  
  #the first connection act, set persistence and tokens
  def initializer(user)
    rebuild_all_cache(user.id) #prevent inconsistences
    # rebuild_task_cache #prevent inconsistences
    user.log_trash = user.log_old
    user.log_old = nil
    user.tkn = rand(1000000)
    user.last_login = Time.now.utc
    user.save
  end
   
  #login process 
  def logg(kuni,occurrence)
    if occurrence == 9
      user_to_send = User.find_by_id(kuni[0])
      user_to_send.log << [occurrence, Time.now, kuni[1], session[:id], session[:name] ] #kuni[0] = user_id, kuni[1] = message
      if user_to_send.save
        true
      else
        false
      end
    elsif occurrence == 10
      owner = User.find_by_id(session[:id])
      owner.log << [occurrence, Time.now, kuni.id, session[:id], session[:name] ]
      if owner.save
        true
      else
        false
      end
    elsif occurrence == 11
      # logg([params[:user_id],escaped_message,kuni.id],11)
      user_to_send = User.find_by_id(kuni[0])
      user_to_send.log << [occurrence, Time.now, kuni[1], session[:id], session[:name], kuni[2] ] #kuni[0] = user_id, kuni[1] = message, kuni[2] = kuni id
      if user_to_send.save
        true
      else
        false
      end
    else
      owner = User.find_by_id(kuni.user_id)
      if owner.id != session[:id]
        owner.log << [occurrence, Time.now, kuni.id, session[:id], session[:name] ]
        if owner.save
          true
        else
          false
        end
      else
        true #he is the owner, dont need a log
      end
    end
  end

  #process the alerts
  def logg_process(log)
    case log[0]
    when 0                
      return t.alerts.a0(log[2],log[3],log[4]) #solution
    when 1               
      return t.alerts.a1(log[2],log[3],log[4]) #comment
    when 2               
      return t.alerts.a2(log[2],log[3],log[4]) #sync task
    when 3               
      return t.alerts.a3(log[2],log[3],log[4]) #copy kuni
    when 4               
      return t.alerts.a4(log[2],log[3],log[4]) #invite to private group
    when 5               
      return t.alerts.a5(log[2],log[3],log[4]) #synched task deleted
    when 6               
      return t.alerts.a6(log[2],log[3],log[4]) #solve synched task
    when 7               
      return t.alerts.a7(log[2],log[3],log[4]) #watched kuni deleted
    when 8               
      return t.alerts.a8(log[2],log[3],log[4]) #kuni cloned deleted
    when 9               
      return t.alerts.a9(log[2],log[3],log[4]) #direct message
    when 10
      return t.alerts.a10(log[2],log[3],log[4]) #welcome message
    when 11
      #[2]message, [3]sender_id, [4]sender_name, [5]kuni_sender
      return t.alerts.a11(log[2],log[3],log[4],log[5]) #bulk alert to members
    else                  
      return 'i know that somethink is going wrong, but i forgot what...'  
    end
  end

  #this function is for copy tasks synched before delete
  def secure_destroy(task, from_task)
    tasks_in_sync = Task.all(:original => task.id)
    solutions_saved = ''
    count = 0
    if !tasks_in_sync.nil?
      tasks_in_sync.each do |task_sinc|
        task.solutions.each do |solution|
          temp_sol = Solution.new
          temp_sol.task_id = task_sinc.id
          temp_sol.message = solution.message
          temp_sol.solve = solution.solve
          temp_sol.links = solution.links
          temp_sol.included_by = solution.included_by
          temp_sol.included_by_id = solution.included_by_id
          temp_sol.mine = solution.mine
          task_sinc.solutions << temp_sol
          count += 1
        end
        task_sinc.is_done = task.in_sync ? Task.find_by_id(task.original).is_done : task.is_done
        task_sinc.in_sync = false
        task_sinc.original = nil
        task_sinc.s_count = count
        task_sinc.sharing_type = task.sharing_type #Kuni.find_by_id(task_sinc.kuni_id).sharing_type
        if task_sinc.save
          if from_task
            logg(Kuni.find_by_id(task_sinc.kuni_id),5)
          end
          solutions_saved << ''
        else
          solutions_saved << 'f'
        end
      end
    end
    if solutions_saved == ''
      task.solutions.each do |solution|
        solution.destroy
      end
      if task.destroy
      else
        solutions_saved << 'f'
      end
    end
    solutions_saved
  end
  
  #main def to read kunis
  def read_kuni (file,kuni)
    if can_see_this kuni
      erubis file    
    end
  end
  
  #secure the access of the kuni
  def can_see_this(kuni)
    if !kuni.nil?
      if kuni.sharing_type == 'private'
        if kuni.permitted_users.include? session[:name] or kuni.user_id == session[:id]
          true
        else
          status 404
        end
      else
        true
      end
    else
      status 404
    end
  end
  
  #dont let access if is not logged
  def authenticate
    if session[:name].nil? or session[:name] == 'guest'
      session[:name] = 'guest'
      session[:id] = "0"
      false
      # redirect '/home'
    else
      true
    end
  end
  
  #special mechanic captcha created by tcha-tcho
  def not_spammer(token)
    if session[:token] == token.to_i
      session[:token] = rand(1000000)
      true
    else
      false
    end
  end
  def not_kuni_spammer(token)
    if session[:kuni_token] == token.to_i
      session[:kuni_token] = rand(1000000)
      true
    else
      false
    end
  end
  
  #refresh changes in all synched kunis
  def sync_changes(task)
    tasks_in_sync = Task.all(:original => task.id)
    solutions_saved = ''
    
    if rebuild_cache(Kuni.find_by_id(task.kuni_id))
      if !tasks_in_sync.nil?
        tasks_in_sync.each do |task_sinc|
          task_sinc.is_done = task.in_sync ? Task.find_by_id(task.original).is_done : task.is_done
          kuni = Kuni.find_by_id(task_sinc.kuni_id)
          if task_sinc.save and rebuild_cache(kuni)
            logg(kuni,6)
            solutions_saved << ''
          else
            solutions_saved << 'f'
          end
        end
      end
    end
    solutions_saved
  end

  #this cache tells the ui how much % was done
  def rebuild_all_cache(user_id)
    user = User.find_by_id(user_id)
    my_kunis = user.kunis.all
    my_kunis.each do |kuni|
      rebuild_cache(kuni)
    end
  end
  
  #this cache tells ui if the task was completed
  def rebuild_task_cache
    user = User.find_by_id(session[:id])
    user.kunis.all.each do |kuni|
      kuni.tasks.all.each do |task|
        puts task.s_count
        task.s_count = task.solutions.count
        task.save
      end
    end
  end
  
  #the main def to count % completed of the kuni
  def rebuild_cache (kuni)
    all_tasks = kuni.tasks
    all_done = all_tasks.all(:is_done => true)
    ratio = 0.0
    if !all_tasks.nil? and !all_done.nil? and all_done.count != 0
      ratio = all_done.count.to_f/all_tasks.count.to_f * 100.0
    else
      ratio = 0
    end
    case ratio
    when 0..1
      kuni.cache = 0
    when 0..10
      kuni.cache = 10
    when 10..20
      kuni.cache = 20
    when 20..30
      kuni.cache = 30
    when 30..40
      kuni.cache = 40
    when 40..50
      kuni.cache = 50
    when 50..60
      kuni.cache = 60
    when 60..70
      kuni.cache = 70
    when 70..80
      kuni.cache = 80
    when 80..90
      kuni.cache = 90
    when 90..100
      kuni.cache = 100
    else
      kuni.cache = 0
    end
    if kuni.save
      true
    else
      false
    end
  end
end

###############################################################################################
#THE DATABASE CONNECTION: PLEASE CREATE A CONNECTION TO A MONGODB DATABASE. 
#HERE IM USING A mongohq.com database.
#MONTOHQ OFFERS FREEDATABASES PLEASE TAKE A LOOK INTO THE SITE.
#
MongoMapper.connection = Mongo::Connection.new('flame.mongohq.com', 27023, {:passenger => true})
MongoMapper.database = 'kunigo_os'
MongoMapper.database.authenticate('kunigo', 'password')

###############################################################################################
#

#mongomapper create Objects from your database... im creating the objects here:
class User
  include MongoMapper::Document
  include BCrypt
  
  key :email, String
  key :name, String
  key :crypted_password, String
  key :log, Array
  key :log_old, Array
  key :log_trash, Array
  key :tkn, String
  key :p_list, Array
  key :last_login, String
  key :listed, Integer
  timestamps!
  
  many :kunis
  many :watcheds
  
  #encrypt passwords!
  def password
    @password ||= Password.new(crypted_password)
  end
  def password=(new_password)
    @password = Password.create(new_password)
    self.crypted_password = @password
  end
end

class Watched
  include MongoMapper::Document
  key :user_id, ObjectId
  key :kuni_id, ObjectId
end

class Kuni
  include MongoMapper::Document
  key :user_id, ObjectId
  key :title, String
  key :sharing_type, String
  key :template, Boolean
  key :cloned_from, ObjectId
  key :disable, Boolean
  key :details, String
  key :image, String
  key :cache, Integer
  key :permitted_users, Array
  key :comments_closed, Boolean
  key :tags, Array
  key :members, Array
  timestamps!

  many :tasks
  many :comments
end

class Task
  include MongoMapper::Document
  key :kuni_id, ObjectId
  key :title, String
  key :sharing_type, String
  key :in_sync, Boolean
  key :is_done, Boolean
  key :closed, Boolean
  key :original, ObjectId
  key :s_count, Integer
  timestamps!
  
  many :solutions
end

class Solution
  include MongoMapper::Document
  key :task_id, ObjectId
  key :message, String
  key :solve, Boolean
  key :links, Array
  key :included_by, String
  key :included_by_id, ObjectId
  key :mine, Boolean
  timestamps!

  # belongs_to :task, :dependent => :destroy

  # def handle_upload( file )
  #   file_to_save = []
  #   file_to_save << file[:type]
  #   file_to_save << File.size(file[:tempfile])
  #   file_to_save << self.id.to_s + File.basename(file[:filename])
  #   file_to_save << File.basename(file[:filename])    #.sub(/[^\w\.\-]/,'_')    lembrar de colocar isso... sanitize filename :P
  #   path = File.join(Dir.pwd, "public/files/", file_to_save[2])
  #   File.open(path, "wb") do |f|
  #     f.write(file[:tempfile].read)
  #   end
  #   self.files << file_to_save
  # end
end

class Comment
  include MongoMapper::Document
  key :kuni_id, ObjectId
  key :included_by, String
  key :message, String
  timestamps!
end

class Email
  include MongoMapper::Document
  key :email, String
  timestamps!
end

#CHANGE THIS CODE TO SECURE YOURS SESSIONS...
use Rack::Session::Cookie, :secret => 'Lorem ipsum dolor sit amet, consectetur adipiscing elit.'


#force the i18n to your local, for now
@@locale = 'pt'
@@home_path = 'none'
@@home_id = 'none'

before do
  session[:locale] = @@locale
end

#main routes
get '/lang/:lang' do
  @@locale = params[:lang]
  redirect '/'
end

get '/home' do
  redirect '/'
end
get '/index' do
  redirect '/'
end

get '/preview' do
  redirect '/'
end

#shortcuts
get '/KUNI/:kuni_id' do
  redirect "/kuni/#{params[:kuni_id]}"
end
get '/k/:kuni_id' do
  redirect "/kuni/#{params[:kuni_id]}"
end
get '/K/:kuni_id' do
  redirect "/kuni/#{params[:kuni_id]}"
end
get '/Kuni/:kuni_id' do
  redirect "/kuni/#{params[:kuni_id]}"
end
get '/USER/:user_id' do
  redirect "/user/#{params[:user_id]}"
end
get '/u/:user_id' do
  redirect "/user/#{params[:user_id]}"
end
get '/U/:user_id' do
  redirect "/user/#{params[:user_id]}"
end
get '/User/:user_id' do
  redirect "/user/#{params[:user_id]}"
end

get '/kuni/:kuni_id' do
  @@home_path = "kuni"
  @@home_id = "#{params[:kuni_id]}"
  redirect '/'
end
get '/user/:user_id' do
  user = User.find_by_name(params[:user_id])
  if !user.nil?
    @@home_id = user.id.to_s
  else
    @@home_id = "not_found" #maybe the name is a mongoid already
  end
  @@home_path = "user"
  redirect '/'
end

get '/?' do
  # @@locale = 'pt'
  
  session[:pre_token] = rand(1000000000)
  if authenticate
    @user_name = ''
    session[:name].to_s.each_char do |letter|
      @user_name << letter + "<br>"
    end
    @guest = false
  else
    @user_name = ''
    t.index.guest.to_s.each_char do |letter|
      @user_name << letter + "<br>"
    end
    @guest = true
  end
  erubis :index
end

#utility routes

post '/login' do
  if params[:login_user].match('@')
    @user = User.find_by_email(params[:login_user].downcase)
  else
    @user = User.find_by_name(params[:login_user].downcase)
  end
  if @user.password == params[:login_password]
    session[:name] = @user.name
    session[:id] = @user.id
    session[:token] = rand(1000000)
    session[:kuni_token] = rand(1000000)
    if initializer @user
      status 200
    end
  else
    status 404
  end
end

#this is used for the ui to see existing users and etc.
post '/test_user' do
  if User.find_by_name(params[:user_to_test].downcase)
    return 'x'
  else
    return 'k'
  end
end
post '/test_email' do
  if User.find_by_email(params[:email_to_test].downcase)
    return 'x'
  else
    return 'k'
  end
end

#main def to create a user (the ui send all data)
post '/create_user' do
  session[:name] = nil
  session[:id] = nil
  session[:token] = nil
  session[:kuni_token] = nil
  if session[:pre_token] == params[:pre_token].to_i
    if !User.find_by_name(params[:reg_user].downcase) and !User.find_by_email(params[:reg_email].downcase) and params[:reg_password] != ''
      user = User.new
      user.email = params[:reg_email].downcase
      user.name = params[:reg_user].downcase
      user.password = params[:reg_password]
      user.last_login = Time.now.utc
      user.listed = 0
      if user.save!
        session[:name] = user.name
        session[:id] = user.id
        session[:token] = rand(1000000)
        session[:kuni_token] = rand(1000000)
        false_kuni = Kuni.new
        logg(false_kuni,10)
        
        #problems with smtp server limit ... log all emails to send welcome later
        log_email = Email.new
        log_email.email = params[:reg_email].downcase
        log_email.save
        # send_mail(params[:reg_email].downcase,t.email.welcome_subject(session[:name]), t.email.welcome(session[:name]))        
      else
        status 404
      end
    end
  else
    status 500
  end
end

#when you click on the name of the guy this is the def called
get '/user_info' do
  if authenticate
    @user = User.find_by_id(session[:id])
    @listed = @user.listed
    @last_login = @user.last_login
    @public_kunis = @user.kunis.all.count
    @solutions_solved = Solution.all(:included_by_id => session[:id],:solve => true,:mine => false).count
    erubis :user_info
  else
    t.messages.not_allowed
  end
end

#change personal data into user configuration screen
post '/change_password' do
  if authenticate
    user = User.find_by_id(session[:id])
    if user.password == params[:actual_password]
      user.password = params[:new_password]
      user.save
      status 200
    else
      status 404
    end
  else
    t.messages.not_allowed
  end
end
post '/change_email' do
  if authenticate
    user = User.find_by_id(session[:id])
    if !User.find_by_email(params[:new_email].downcase)
      user.email = params[:new_email].downcase
      user.save
      status 200
    else
      status 404
    end
  else
    t.messages.not_allowed
  end
end

#this will use a smtp server to contact user with a special change password system created by tcha-tcho
post '/forgot_password' do
  if params[:login_user].match('@')
    @user = User.find_by_email(params[:login_user].downcase)
  else
    @user = User.find_by_name(params[:login_user].downcase)
  end
  if !@user.nil?
    @user.tkn = rand(1000000)
    @secured_link = "http://www.kunigo.com/reset_password/#{@user.id}/#{@user.tkn}"
    @user.save!
    send_mail(@user.email,t.email.forgot_subject(@user.name), t.email.forgot(@user.name,@secured_link))
  else
    status 404
  end
end
get '/reset_password/:user_id/:reset_token' do
  user = User.find_by_id(params[:user_id])
  if user.tkn == params[:reset_token]
    erubis :change_password
  else
    t.messages.link_destroyed
  end
end
post '/process_reset_password' do
  @user = User.find_by_id(params[:id])
  # random_password = Array.new(10).map { (65 + rand(58)).chr }.join
  if @user.email == params[:reg_email].downcase and @user.name == params[:reg_user].downcase and @user.tkn == params[:token]
    @user.tkn = rand(1000000)
    @user.password = params[:reg_password]
    @user.tkn = rand(1000000)
    if @user.save!
      status 200
    else
      status 404
    end
  else
    status 404
  end
end


#p_list process - p_list is people list (a friend list)
get '/p_list' do
  if authenticate
    user = User.find_by_id(session[:id])
    @p_list = user.p_list
    erubis :p_list
  else
    t.messages.not_allowed
  end
end
post '/remove_from_p_list' do
  if authenticate
    user = User.find_by_id(session[:id])
    ids_to_del = params[:to_del].split(",")
    ids_to_del.each do |id|
      user.p_list.delete_if {|u| u[0] == id}
      if !id.nil? and id != ""
        user_to_list = User.find_by_id(id)
        user_to_list.listed -= 1
        user_to_list.save
      end
    end
    if user.save
      status 200
    else
      status 404
    end
  else
    t.messages.not_allowed
  end
end
post '/add_in_p_list' do
  if authenticate
    user = User.find_by_id(session[:id])
    new_user = [params[:u_id],params[:name]]
    if user.p_list.include? new_user
      status 404
    else
      user.p_list << new_user
      user_to_list = User.find_by_id(params[:u_id])
      user_to_list.listed += 1
      user_to_list.save
      if user.save
        status 200
      else
        status 404
      end
    end
  else
    t.messages.not_allowed
  end
end

#main def to bring the left bar kunis
get '/kunilist/my' do
  if authenticate
    user = User.find_by_id(session[:id])
    @mykunis = user.kunis.all(:order => 'created_at desc')
    erubis :kunilistmy
  else
    erubis :kunilistmy_guest
  end
end

#main def to bring the right bar kunis
get '/kunilist/watched' do
  if authenticate
    user = User.find_by_id(session[:id])
    @watchedkunis = user.watcheds.all(:order => 'created_at desc')
    erubis :kunilistwatched
  else
    @selecteds = []
    kunis = t.home.selected_kuni.split(";")
    kunis.each do |kuni|
      @selecteds << Kuni.find_by_id(kuni)
    end
    erubis :kunilistwatched_guest
  end
end

#sometimes we need to refresh the kuni bar
get '/reload_bar/:id' do
  if authenticate
    kuni = Kuni.find_by_id(params[:id])
    if kuni.template
      "x"
    else
      if rebuild_cache(kuni)
        kuni.cache.to_s
      else
        status 404
      end
    end
  else
    t.messages.not_allowed
  end
end

# get alerts
get '/user_alerts' do
  if authenticate
    @user = User.find_by_id(session[:id])
    erubis :alerts
  else
    t.messages.not_allowed
  end
end
get '/update_alerts' do
  if authenticate
    user = User.find_by_id(session[:id])
    user.log.length.to_s
  else
    0.to_s
  end
end

#reading kunis or tasks into the viewer (central place) : ok a little repetition here to be changed
get '/read_kuni_my/:id' do
  if authenticate
    @kuni = Kuni.find_by_id(params[:id])
    @member = @kuni.members.include? [session[:name],session[:id]]
    @guest = false
    read_kuni(:read_kuni_my, @kuni)
  else
    @kuni = Kuni.find_by_id(params[:id])
    @member = false
    @guest = true
    read_kuni(:read_kuni_my, @kuni)
  end
end

get '/read_kuni_watched/:id' do
  if authenticate
    @kuni = Kuni.find_by_id(params[:id])
    @member = @kuni.members.include? [session[:name],session[:id]]
    @guest = false
    read_kuni(:read_kuni_watched, @kuni)
  else
    @kuni = Kuni.find_by_id(params[:id])
    @member = false
    @guest = true
    read_kuni(:read_kuni_watched, @kuni)
  end
end

get '/read_kuni_searched/:id' do
  if authenticate
    @kuni = Kuni.find_by_id(params[:id])
    @member = @kuni.members.include? [session[:name],session[:id]]
    @guest = false
    read_kuni(:read_kuni_searched, @kuni)
  else
    @kuni = Kuni.find_by_id(params[:id])
    @member = false
    @guest = true
    read_kuni(:read_kuni_searched, @kuni)
  end
end

get '/read_task_searched/:id' do
  @task = Task.find_by_id(params[:id])
  kuni = Kuni.find_by_id(@task.kuni_id)
  if kuni.sharing_type == 'public'
    @task_image = ''
    if kuni.template
      @task_image = 'template'
    else
      if @task.is_done
        @task_image = 'completed'
      else
        @task_image = 'noncompleted'
      end
    end    
    @solutions = @task.solutions.all
    erubis :read_task_searched
  else
    'private'
  end
end

get '/read_user_searched/:id' do
  if authenticate
    @guest = false
  else
    @guest = true
  end
  @user = User.find_by_id(params[:id])
  @its_me = params[:id] == session[:id].to_s
  @listed = @user.listed
  @last_login = @user.last_login
  @public_kunis = @user.kunis.all(:sharing_type => 'public')
  @solutions_solved = Solution.all(:included_by_id => params[:id],:solve => true,:mine => false).count
  erubis :read_user_searched
end

#tasks operations
get '/kuni/tasks/:id' do
  if authenticate
    @guest = false
  else
    @guest = true
  end
  @kuni = Kuni.find_by_id(params[:id])
  if can_see_this @kuni
    @user_id = session[:id]
    @kuni_user_id = @kuni.user_id
    @kuni_user_name = User.find_by_id(@kuni_user_id).name
    @he_can_see = @kuni.user_id == @user_id ? true : false
    @tasks = []
    @tasks_in_sync = []
    all_tasks = @kuni.tasks.all
    all_tasks.each do |task|
      if task.in_sync
        @tasks_in_sync << task
      else
        @tasks << task
      end
    end
    erubis :tasks
  end
end

get '/kuni/task/solutions/:id' do
  if authenticate
    @guest = false
  else
    @guest = true
  end
  task = Task.find_by_id(params[:id])
  kuni = Kuni.find_by_id(task.kuni_id)
  if can_see_this kuni
    @taskid = params[:id]
    @userid = session[:id]
    @is_template = kuni.template
    @in_sync = task.in_sync
    if @in_sync
      task_sync = Task.find_by_id(task.original)
      @closed = task_sync.closed
      kuni_original = Kuni.find_by_id(task_sync.kuni_id)
      @kuni_id = kuni_original.id
      @kuni_userid = kuni_original.user_id
      @solutions = task_sync.solutions.all(:order => 'created_at desc')
    else
      @closed = task.closed
      @kuni_userid = kuni.user_id
      @solutions = task.solutions.all(:order => 'created_at desc')
    end
    erubis :solutions
  end
end

#get all kunis that are using this as base
get '/kuni/network/:id' do
  @kuni = Kuni.find_by_id(params[:id])
  if can_see_this @kuni
    @full_copy_count = Kuni.all(:cloned_from => @kuni.id).count
    tasks = @kuni.tasks.all(:in_sync => false)
    @tasks_count = []
    if tasks.length > 0
      tasks.each do |task|
          @tasks_count << [task,Task.all(:original => task.id).count]
      end
    else
      @tasks_count = nil
    end
    erubis :network
  end
end

#get all tasks that are synched with that id
get '/syncheds/:task_id' do
  tasks = Task.all(:original => params[:task_id])
  @syncheds = []
  if tasks.length > 0
    tasks.each do |task|
      kuni = Kuni.find_by_id(task.kuni_id)
      @syncheds << kuni if kuni.sharing_type == "public"
    end
  else
    @syncheds = nil
  end
  erubis :syncheds
end

#retrieve comments for that kuni id
get '/kuni/comments/:id' do
  if authenticate
    @guest = false
  else
    @guest = true
  end
  @kuni = Kuni.find_by_id(params[:id])
  @comments = @kuni.comments.all(:order => 'created_at desc')
  @user_name = session[:name]
  @owner = User.find_by_id(@kuni.user_id).name
  erubis :comments
end

#the user will close anyone for make comments
post '/close_comments/:kuni_id' do
  if authenticate
    kuni = Kuni.find_by_id(params[:kuni_id])
    if can_see_this kuni
      kuni.comments_closed = !kuni.comments_closed
      if kuni.save
        status 200
      else
        status 404
      end
    end
  else
    t.messages.not_allowed
  end
end

#retrieve the details text inserted by the user
get '/kuni/details/:kuni_id' do
  @kuni = Kuni.find_by_id(params[:kuni_id])
  if can_see_this @kuni
    @he_can_see = @kuni.user_id == session[:id] ? true : false
    erubis :details
  end
end

#change details
post '/kuni/change_details/:kuni_id' do
  if authenticate
    @kuni = Kuni.find_by_id(params[:kuni_id])
    if can_see_this @kuni
      @kuni.details = params[:new_details]
      if @kuni.save
        status 200
      else
        status 404
      end
    end
  else
    t.messages.not_allowed
  end
end

#kunis could have a image url
post '/kuni/change_image/:kuni_id' do
  if authenticate
    @kuni = Kuni.find_by_id(params[:kuni_id])
    if can_see_this @kuni
      @kuni.image = params[:image] == "" ? nil : params[:image]
      if @kuni.save
        status 200
      else
        status 404
      end
    end
  else
    t.messages.not_allowed
  end
end

#tags was asked by users
post '/kuni/update_tags/:kuni_id' do
  if authenticate
    @kuni = Kuni.find_by_id(params[:kuni_id])
    if can_see_this @kuni
      @kuni.tags = params[:tags] == "" ? nil : params[:tags].split(',')
      if @kuni.save
        status 200
      else
        status 404
      end
    end
  else
    t.messages.not_allowed
  end
end

#HERE GOES ALL MAIN FORM ENTRIES ALLOWED BY THE SOFTWARE
post '/create_kuni' do
  if authenticate
    if not_kuni_spammer params[:kuni_token]
      user = User.find_by_id(session[:id])
      kuni = Kuni.new
      kuni.title = params[:title]
      kuni.template = params[:template]
      kuni.sharing_type = params[:access]
      kuni.cache = 0
      user.kunis << kuni
      if user.save
        kuni.id.to_s
      else
        status 404
      end
    else
      status 500
    end
  else
    t.messages.not_allowed
  end
end
post '/create_task/:kuniid' do
  if authenticate
    if not_spammer params[:token]
      user = User.find_by_id(session[:id])
      kuni = Kuni.find_by_id(params[:kuniid])
      if user.id == kuni.user_id
        kuni.tasks.create({
          :title => params[:title],
          :is_done => false,
          :in_sync => false,
          :closed => false,
          :s_count => 0,
          :sharing_type => kuni.sharing_type
        })
      end
    else
      status 500
    end
  else
    t.messages.not_allowed
  end
end
post '/change_permissions/:kuniid' do
  if authenticate
    user = User.find_by_id(session[:id])
    kuni = Kuni.find_by_id(params[:kuniid])
    if user.id == kuni.user_id
      kuni.permitted_users = params[:users_permitted].split(",")
      kuni.save
    end
  else
    t.messages.not_allowed
  end
end
post '/send_invites/:kuniid' do
  if authenticate
    user = User.find_by_id(session[:id])
    kuni = Kuni.find_by_id(params[:kuniid])
    if user.id == kuni.user_id
      kuni.permitted_users.each do |user_name|
        if !user_name.nil?
          invited = User.find_by_name(user_name)
          if !invited.nil?
            invited.log << [4, Time.now, kuni.id, user.id, user.name ]
            invited.save
          end
        end
      end
    end
  else
    t.messages.not_allowed
  end
end
post '/add_comment/:kuniid' do
  if authenticate
    if not_spammer params[:token]
      kuni = Kuni.find_by_id(params[:kuniid])
      comment = Comment.new
      comment.included_by = session[:name]
      comment.message = params[:commentary]
      kuni.comments << comment
      if kuni.save
        logg(kuni,1)
        status 200
      else
        status 404
      end
    else
      status 500
    end
  else
    t.messages.not_allowed
  end
end
post '/add_solution/:taskid' do
  if authenticate
    if not_spammer params[:token]
      task = Task.find_by_id(params[:taskid])
      kuni = Kuni.find_by_id(task.kuni_id)
      if task.in_sync
        task_original = Task.find_by_id(task.original)
        if task_original.sharing_type == 'public'
          solution = task_original.solutions.create({
            :message => params[:solution],
            :included_by => session[:name],
            :included_by_id => session[:id],
            :mine => kuni.user_id == session[:id] ? true : false,
            :links => params[:links].split(','),
            :solve => false
          })
        else
          if can_see_this kuni
            solution = task_original.solutions.create({
              :message => params[:solution],
              :included_by => session[:name],
              :included_by_id => session[:id],
              :mine => kuni.user_id == session[:id] ? true : false,
              :links => params[:links].split(','),
              :solve => false
            })
          else
            status 404
          end
        end
      else
        solution = task.solutions.create({
          :message => params[:solution],
          :included_by => session[:name],
          :included_by_id => session[:id],
          :mine => kuni.user_id == session[:id] ? true : false,
          :links => params[:links].split(','),
          :solve => false
        })
      end
      task.s_count += 1
      if solution.save and task.save
        logg(kuni,0)
        solution.id.to_s
      else
        status 404
      end
    else
      status 500
    end
  else
    t.messages.not_allowed
  end
end
post '/add_message/:user_id' do
  if authenticate
    if not_spammer params[:token]
      escaped_message = h params[:message]
      if logg([params[:user_id],escaped_message],9)
        status 200
      else
        status 404
      end
    else
      status 500
    end
  else
    t.messages.not_allowed
  end
end

#ACTIONS!
get '/add_member/:kuni_id' do
  if authenticate
    kuni = Kuni.find_by_id(params[:kuni_id])
    if !kuni.members.include? [session[:name],session[:id]]
      kuni.members << [session[:name], session[:id]]
      if kuni.save
        status 200
      else
        status 404
      end
    else
      status 404
    end
  else
    t.messages.not_allowed
  end
end
get '/delete_member/:kuni_id' do
  if authenticate
    kuni = Kuni.find_by_id(params[:kuni_id])
    if kuni.members.include? [session[:name],session[:id]]
      kuni.members.delete_if {|member| member == [session[:name],session[:id]]}
      if kuni.save
        status 200
      else
        status 404
      end
    else
      status 404
    end
  else
    t.messages.not_allowed
  end
end
get '/members_list/:kuni_id' do
  @kuni = Kuni.find_by_id(params[:kuni_id])
  @owner = @kuni.user_id == session[:id]
  erubis :members
end
post '/send_alerts/:kuni_id' do
  if authenticate
    kuni = Kuni.find_by_id(params[:kuni_id])
    escaped_message = h params[:message]
    dirty = ''
    if kuni.user_id == session[:id]
      kuni.members.each do |member|
        if logg([member[1],escaped_message,kuni.id],11)
          dirty << ''
        else
          dirty << 'x'
        end
      end
      if dirty == ''
        status 200
      else
        status 404
      end
    else
      status 500
    end
  else
    t.messages.not_allowed
  end
end

get '/exclude_comment/:id' do
  if authenticate
    comment = Comment.find_by_id(params[:id])
    if comment.destroy
      status 200
    else
      status 404
    end
  else
    t.messages.not_allowed
  end
end
post '/delete_tasks/:kuni_id' do
  if authenticate
    errors = ''
    tasks_ids = params[:tasks].split(',')
    kuni = Kuni.find_by_id(params[:kuni_id])
    if kuni.user_id == session[:id]
      tasks_ids.each do |task_id|
        task = Task.find_by_id(task_id)
        if !secure_destroy(task,true) == ''
          errors << 'x'
        end
      end
      if errors == ''
        status 200
      else
        status 404
      end
    else
      status 404
    end
  else
    t.messages.not_allowed
  end
end

post '/broke_syncs/:kuni_id' do
  if authenticate
    errors = ''
    tasks_ids = params[:tasks].split(',')
    # create a method to test ownership
    kuni = Kuni.find_by_id(params[:kuni_id])
    if kuni.user_id == session[:id]
      tasks_ids.each do |task_id|
      
        task = Task.find_by_id(task_id)
        task_original = Task.find_by_id(task.original)
        count = 0
        if !task_original.nil?
          task_original.solutions.each do |solution|
            temp_sol = Solution.new
            temp_sol.task_id = task.id
            temp_sol.message = solution.message
            temp_sol.solve = solution.solve
            temp_sol.links = solution.links
            temp_sol.included_by = solution.included_by
            temp_sol.included_by_id = solution.included_by_id
            temp_sol.mine = solution.mine
            task.solutions << temp_sol
            count += 1
          end
          task.is_done = task_original.is_done
          task.closed = task_original.closed
          task.in_sync = false
          task.original = nil
          task.s_count = count
          if !task.save
            errors << 'x'
          end
        end  
      end
      if errors == ''
        status 200
      else
        status 404
      end
    else
      status 404
    end
  else
    t.messages.not_allowed
  end
end
post '/close_tasks/:kuni_id' do
  if authenticate
    errors = ''
    tasks_ids = params[:tasks].split(',')
    # create a method to test ownership
    kuni = Kuni.find_by_id(params[:kuni_id])
    if kuni.user_id == session[:id]
      tasks_ids.each do |task_id|
        task = Task.find_by_id(task_id)
        if !task.in_sync
          task.closed = !task.closed
          if !task.save
            errors << 'x'
          end
        end
      end
      if errors == ''
        status 200
      else
        status 404
      end
    else
      status 404
    end
  else
    t.messages.not_allowed
  end
end
get '/delete_solution/:id' do
  if authenticate
    solution = Solution.find_by_id(params[:id])
    task = Task.find_by_id(solution.task_id)
    if solution.solve
      task.is_done = false
    end
    task.s_count -= 1
    if solution.destroy and task.save
      if sync_changes(task) == ''
        status 200
      else
        status 404
      end
    else
      status 404
    end
  else
    t.messages.not_allowed
  end
end
get '/solved/:id' do
  if authenticate
    solution = Solution.find_by_id(params[:id])
    task = Task.find_by_id(solution.task_id)
    task.solutions.each do |sltion|
      sltion.solve = false
      if !sltion.save
        status 404
      end
    end
    solution.solve = true
    task.is_done = true
    if task.save and solution.save
      if sync_changes(task) == ''
        status 200
      else
        status 404
      end
    else
      status 404
    end
  else
    t.messages.not_allowed
  end
end
post '/mark_task_solved/:kuni_id' do
  if authenticate
    errors = ''
    tasks_ids = params[:tasks].split(',')
    kuni = Kuni.find_by_id(params[:kuni_id])
    if kuni.user_id == session[:id]
      tasks_ids.each do |task_id|
        task = Task.find_by_id(task_id)
        if !task.in_sync
          task.is_done = !task.is_done
        end
        if task.save
          if sync_changes(task) == ''
            status 200
          else
            status 404
          end
        else
          errors << 'x'
        end
      end
      if errors == ''
        status 200
      else
        status 404
      end
    else
      status 404
    end
  else
    t.messages.not_allowed
  end
end

post '/copy_tasks/:kuni_id' do #drag event
  if authenticate
    errors = ''
    tasks_ids = params[:tasks].split(',')
    kuni = Kuni.find_by_id(params[:kuni_id])
    if kuni.user_id == session[:id]
      tasks_ids.each do |task_id|
        task = Task.find_by_id(task_id)
        new_task = Task.new
        new_task.title = task.title
        new_task.is_done = task.in_sync ? Task.find_by_id(task.original).is_done : task.is_done
        new_task.closed = task.in_sync ? Task.find_by_id(task.original).closed : task.closed
        new_task.original = task.in_sync ? task.original : task.id
        new_task.s_count = task.s_count
        kuni.template ? new_task.in_sync = false : new_task.in_sync = true
        if !(kuni.tasks << new_task)
          errors << 'x'
        end
      end
      if errors == ''
        logg(Kuni.find_by_id(params[:kuni_from]),2)
        status 200
      else
        status 404
      end
    else
      status 404
    end
  else
    t.messages.not_allowed
  end
end

get '/delete/:id' do #kuni
  if authenticate
    kuni = Kuni.find_by_id(params[:id])
    user = User.find_by_id(session[:id])
    if kuni.user_id == session[:id]
      solutions_saved = ''
      kuni.tasks.each do |task|
        if !secure_destroy(task,false) == ''
          solutions_saved << 'f'
        end
      end
      kuni.comments.each do |comment|
        comment.destroy
      end
      if solutions_saved == ''
        #log process
        watcheds = Watched.all(:kuni_id => kuni.id)
        watcheds.each do |watched|
          owner = User.find_by_id(watched.user_id)
          if !owner.nil?
            owner.log << [7, Time.now, kuni.id, user.id, user.name ]
            owner.save
          end
        end
        kuni_copies = Kuni.all(:cloned_from => kuni.id)
        kuni_copies.each do |kuni_copy|
          logg(kuni_copy,8)
        end
        if kuni.destroy
          status 200
        else
          status 404
        end
      else
        status 404
      end
    else
      status 404
    end
  else
    t.messages.not_allowed
  end
end

get '/watch/:id' do
  if authenticate
    user = User.find_by_id(session[:id])
    if !user.watcheds.find_by_kuni_id(params[:id])
      new_watched = Watched.new
      new_watched.kuni_id = params[:id]
      user.watcheds << new_watched
      if user.save
        status 200
      else
        status 404
      end
      @kuni = Kuni.find_by_id(new_watched.kuni_id)
      erubis :read_kuni_watched
    else
      status 404
    end
  else
    t.messages.not_allowed
  end
end
get '/remove/:id' do #kuni from the watched
  if authenticate
    user = User.find_by_id(session[:id])
    watched = user.watcheds.find_by_kuni_id(params[:id])
    if watched.destroy
      status 200
    else
      status 404
    end
  else
    t.messages.not_allowed
  end
end

#this is a complex actions... this will be fired when you click the fork button
get '/fork/:id' do
  if authenticate
    kuni = Kuni.find_by_id(params[:id])
    user = User.find_by_id(session[:id])
    if kuni.template
      new_kuni = Kuni.new
      new_kuni.title = kuni.title
      new_kuni.sharing_type = kuni.sharing_type
      new_kuni.template = false
      new_kuni.cloned_from = kuni.id
      new_kuni.cache = kuni.cache
      new_kuni.details = kuni.details
      new_kuni.image = kuni.image
      new_kuni.tags = kuni.tags
    
      kuni.tasks.each do |task|
        new_task = Task.new
        new_task.title = task.title
        new_task.is_done = task.is_done
        new_task.sharing_type = task.sharing_type
        new_task.in_sync = false
        new_task.closed = false
        new_task.original = nil
        new_task.s_count = 0
        new_kuni.tasks << new_task
      end
      user.kunis << new_kuni
      if user.save
        logg(kuni,3)
        status 200
      else
        status 404
      end
    else
      new_kuni = Kuni.new
      new_kuni.title = kuni.title
      new_kuni.sharing_type = kuni.sharing_type
      new_kuni.template = kuni.template
      new_kuni.cloned_from = kuni.id
      new_kuni.disable = false
      new_kuni.cache = kuni.cache
      new_kuni.details = kuni.details
      new_kuni.image = kuni.image
      new_kuni.tags = kuni.tags
    
      kuni.tasks.each do |task|
        task_tested = task.in_sync ? Task.find_by_id(task.original) : task
        new_task = Task.new
        new_task.title = task.title
        new_task.sharing_type = task.sharing_type
        new_task.in_sync = true
        new_task.is_done = task_tested.is_done
        new_task.closed = task_tested.closed
        new_task.original = task.in_sync ? task.original : task.id
        new_task.s_count = task_tested.s_count
        new_kuni.tasks << new_task
      end
      user.kunis << new_kuni
      if user.save
        logg(kuni,3)
        status 200
      else
        status 404
      end
    end
    @kuni = new_kuni
    erubis :read_kuni_my
  else
    t.messages.not_allowed
  end
end
get '/make_public/:id' do #kuni
  if authenticate
    kuni = Kuni.find_by_id(params[:id])
    if kuni.user_id == session[:id]
      kuni.sharing_type = 'public'
      tasks = kuni.tasks
      tasks.each do |task|
        task.sharing_type = 'public'
        task.save
      end
      if kuni.save
        kuni.id.to_s
      else
        status 404
      end
    else
      status 404
    end
  else
    t.messages.not_allowed
  end
end

post '/search' do
  @type = params[:filter]
  re = Regexp.new(Regexp.escape(params[:term]), Regexp::IGNORECASE )#.to_json 
	case @type
  	when "kuni"
      all_kunis = Kuni.all(:sharing_type => "public",:template => false, :title => re, :order => 'created_at desc')
  	  all_kunis.delete_if { |kuni| kuni.user_id == session[:id]}
  	  @results = all_kunis
      all_by_tags = Kuni.all(:sharing_type => "public", :tags => re, :order => 'created_at desc')
      # all_by_tags.delete_if { |kuni| kuni.user_id == session[:id]}
      @results_tags = all_by_tags
    when "task"
      @results = Task.all(:sharing_type => "public",:title => re,:in_sync => false, :order => 'created_at desc')
    when "mytasks"
      @results = []
      User.find_by_id(session[:id]).kunis.each do |kuni|
        kuni.tasks.each do |task|
          if !task.in_sync and !re.match(task.title).nil?
            @results << task
          end
        end
      end
      @results
  	when "template"
  	  all_templates = Kuni.all(:sharing_type => "public",:template => true,:title => re, :order => 'created_at desc')
  	  all_templates.delete_if { |kuni_temp| kuni_temp.user_id == session[:id]}
  	  @results = all_templates
    when "user"
      @results = User.all(:name => re)
    when "all"
      @results = Kuni.all(:sharing_type => "public", :order => 'created_at desc',:limit => 100)
    when "member"
      # @results = Kuni.all(:members => [session[:name],session[:id]])  -- i need to better this search
      all_kunis = Kuni.all
      all_kunis.delete_if {|kuni| !kuni.members.include? [session[:name],session[:id]]}
      @results = all_kunis
	end
  erubis :search_result
end

#this is used into the ui to suggest users as the user type
get '/gimeusers' do
  re = Regexp.new(Regexp.escape(params[:tag]), Regexp::IGNORECASE )#.to_json 
  new_users = '['
  User.all(:name => re).each do |u|
    new_users << '{"caption":"'+u.name+'","value":"'+u.name+'"},'
  end
  new_users << '{}]'
  return new_users
end

get '/logout' do
  session[:name] = nil
  session[:id] = nil
  session[:token] = nil
  session[:kuni_token] = nil
  redirect '/'
end 

get '/contact' do
  erubis :contact
end

#emptys
get '/emptyviewer' do
  erubis :emptyviewer
end
get '/emptymylist' do
  erubis :emptymylist
end
get '/emptywatchedlist' do
  erubis :emptywatchedlist
end

get '/load_home' do
  @info = t.home.info(User.all.count, Kuni.all.count)
  erubis :home
end

#javascript need some configuration before be served to the user
get '/allscripts' do
  if authenticate
    @guest = false
  else
    @guest = true
  end
  @home_path = @@home_path
  @@home_path = 'none'
  @home_id = @@home_id
  @@home_id = 'none'
  erubis :all_js
end

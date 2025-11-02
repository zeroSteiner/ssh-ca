namespace :db do
  CONTAINER_NAME = 'sshkeys-postgres'
  DB_NAME = 'sshkeys'
  DB_USER = 'sshkeys'
  DB_PASS = 'development'
  DB_PORT = 5432
  CONNECTION_STRING="postgresql://#{DB_USER}:#{DB_PASS}@localhost:#{DB_PORT}/#{DB_NAME}".freeze
  IMAGE = 'docker.io/postgres:16-alpine'

  desc "Pull PostgreSQL image"
  task :pull do
    puts "Pulling PostgreSQL image..."
    sh "podman pull #{IMAGE}"
  end

  desc "Start PostgreSQL database container"
  task :start => :pull do
    # Check if container already exists
    if `podman ps -a --filter name=#{CONTAINER_NAME} --format '{{.Names}}'`.strip == CONTAINER_NAME
      # Container exists, just start it if it's stopped
      if `podman ps --filter name=#{CONTAINER_NAME} --format '{{.Names}}'`.strip.empty?
        puts "Starting existing container..."
        sh "podman start #{CONTAINER_NAME}"
      else
        puts "Container already running"
      end
    else
      # Create and start new container
      puts "Creating and starting PostgreSQL container..."
      sh <<~CMD
        podman run -d \
          --name #{CONTAINER_NAME} \
          -e POSTGRES_DB=#{DB_NAME} \
          -e POSTGRES_USER=#{DB_USER} \
          -e POSTGRES_PASSWORD=#{DB_PASS} \
          -p #{DB_PORT}:5432 \
          #{IMAGE}
      CMD

      puts "Waiting for PostgreSQL to be ready..."
      max_attempts = 30
      attempts = 0
      until system("podman exec #{CONTAINER_NAME} pg_isready -q") || attempts >= max_attempts
        sleep 1
        attempts += 1
        print "."
      end
      puts

      if attempts >= max_attempts
        puts "ERROR: PostgreSQL failed to start within 30 seconds"
        exit 1
      end
    end

    puts "\nConnection string:"
    puts "export SSH_CA_DATABASE_URI=\"#{CONNECTION_STRING}\""
  end

  desc "Stop PostgreSQL database container"
  task :stop do
    if `podman ps --filter name=#{CONTAINER_NAME} --format '{{.Names}}'`.strip == CONTAINER_NAME
      puts "Stopping PostgreSQL container..."
      sh "podman stop #{CONTAINER_NAME}"
    else
      puts "Container not running"
    end
  end

  desc "Remove PostgreSQL database container"
  task :remove => :stop do
    if `podman ps -a --filter name=#{CONTAINER_NAME} --format '{{.Names}}'`.strip == CONTAINER_NAME
      puts "Removing PostgreSQL container..."
      sh "podman rm #{CONTAINER_NAME}"
    else
      puts "Container does not exist"
    end
  end

  desc "Reset database (stop, remove, and start fresh)"
  task :reset => [:remove, :start]

  desc "Start an interactive console session"
  task :console => :start do
    sh "psql \"#{CONNECTION_STRING}\""
  end
end

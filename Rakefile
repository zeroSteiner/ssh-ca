task default: %i[clean build docs:mandoc]

EXECUTABLE = 'ssh-ca'.freeze

desc "Remove built artifacts from disk"
task :clean do
  puts "removing artifacts..."
  rm_rf FileList["docs", EXECUTABLE]
end

desc "Build the project artifacts"
task :build do
  puts "building artifacts..."
  sh "bashly generate"
end

desc "Install files for local usage"
task install: %i[ build docs:mandoc ]
task :install do
  prefix = ENV['PREFIX'] || (Process.uid == 0 ? '/usr/local' : File.expand_path('~/.local'))
  puts "installing to: #{prefix}..."

  bin_dir = File.join(prefix, 'bin')
  FileUtils.mkdir_p(bin_dir)
  FileUtils.install(EXECUTABLE, File.join(bin_dir, EXECUTABLE), mode: 0755)

  # Install man pages
  man_base_dir = File.join(prefix, 'share/man')
  Dir.glob('docs/mandoc/*.?').each do |man_file|
    # Extract section number from filename (e.g., mybinary.1 -> 1)
    section = File.extname(man_file)[1..]
    man_section_dir = File.join(man_base_dir, "man#{section}")

    FileUtils.mkdir_p(man_section_dir)
    FileUtils.install(man_file, File.join(man_section_dir, File.basename(man_file)), mode: 0644)
  end
end

Dir.glob('tasks/*.rake').sort.each { |r| import r }

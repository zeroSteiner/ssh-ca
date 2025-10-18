namespace :docs do
  desc "Build documentation in all formats"
  task all: %i[ mandoc markdown ]

  desc "Build manpage docs"
  task :mandoc do
    puts "building mandoc pages..."
    sh "bashly render :mandoc docs/mandoc"
  end
  task :man => :mandoc

  desc "Build markdown docs"
  task :markdown do
    puts "building markdown pages..."
    sh "bashly render :markdown docs/markdown"
  end
  task :md => :markdown
end

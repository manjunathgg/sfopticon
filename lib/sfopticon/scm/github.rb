require 'git'
require 'octokit'
require 'fileutils'

# @note Please see {SfOpticon::Scm::Base} for documentation
class SfOpticon::Scm::Github < SfOpticon::Scm::Base
	#@!attribute repo_url
	#  @return [String] The full URL to the remote repository
	attr_accessor :repo_url

	def self.create_remote_repo(name, opts = {})
		SfOpticon::Logger.info { "Creating remote repository #{name}" }
		repo = self.new(name, opts)
		repo.create_repo

		repo
	end

	def self.create_branch(prod,name)
		SfOpticon::Logger.info { "Creating branch #{name} from #{prod.repo_name}"}
		repo = self.new(name)
		repo.create_branch(prod.repo_url)

		repo
	end

	def initialize(name, opts = {})
		@repo_name = name
		@log = SfOpticon::Logger

		## Merge in any specified properties
		@config = SfOpticon::Settings.scm
		@config.deep_merge! opts

		## Entry point for all things github
		@octo = Octokit::Client.new :login => @config.username,
		                            :password => @config.password

		# We have to insert the username/password into the URL for
		# adding the remote
		auth_url = @config.url.gsub /(https?:\/\/)(.*)/,
		                           "\\1#{@config.username}:#{@config.password}@\\2"

		@repo_url = "#{auth_url}/#{@repo_name}"
		@repo_path = Octokit::Repository.from_url @repo_url
		@repo = @octo.repository? @repo_path



		## Local path
		@local_path = "#{@config.local_path}/#{@repo_name}"

		if File.exist? @local_path
			@git = Git.open(@local_path)
		end

		@log.debug {
			"@repo_name = #{@repo_name}
			 @repo_url = #{@repo_url}
			 @repo_path = #{@repo_path}
			 @repo = #{@repo}
			 @local_path = #{@local_path}"
		}
	end

	def add_changes
		@git.add(:all => true)
	end

	def commit(message)
		@git.commit(message)
	end

	def push
		@git.push('origin')
	end

	def repo_exists?
		!!@repo
	end

	# Creates a remote repository on GitHub
	def create_repo 
		@log.info { "Creating repository #{@repo_path}" }

		if repo_exists?
			@log.debug { "Repository #{@repo_path} found"  }
		else
			@log.debug { "Executing @octo.create_repo('#{@repo_name}')"}
			@repo = @octo.create_repo(@repo_name, @config.options)
			create_master
		end

		@repo
	end

	# Creates a branch
	def create_branch(repo_url)
		@log.info { "Creating branch #{@repo_name}" }
		@git = Git.clone(repo_url, @local_path)
		@git.branch(@repo_name).in_branch('Branch Init') {
			update_readme
		}
		@git.checkout(@repo_name)

		@git.push('origin', @repo_name)
	end

	# Creates the master branch on Github by adding a README with
	# the timestamp of creation
	def create_master(path = @local_path)
		@log.info { "Creating master branch at #{path} for #{path} "}

		FileUtils.rm_rf(path)
		FileUtils.mkdir_p(path)
		@git = Git.init(path)
		
		update_readme
		add_changes
		@git.commit('Repository Init')

		# Finalize
		@git.add_remote('origin', @repo_url)
		@git.push		
	end

	def update_readme
		File.open("#{@local_path}/README", 'w') do |f|
			f.puts("Repository init at #{DateTime.now}")
		end			
	end
end

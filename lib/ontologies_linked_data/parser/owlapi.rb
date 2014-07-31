require 'open3'

module LinkedData
  module Parser
    class RepositoryFoldersError < Parser::ParserException
    end
    class InputFileNotFoundError < Parser::ParserException
    end
    class MasterFileMissingException < Parser::ParserException
    end
    class RDFFileNotGeneratedException < Parser::ParserException
    end

    class OWLAPICommand
      def initialize(input_file, output_repo, opts = {})
        @owlapi_wrapper_jar_path = LinkedData.bindir + "/owlapi_wrapper.jar"
        @input_file = input_file
        @output_repo = output_repo
        @master_file = opts[:master_file]
        @logger = opts[:logger] || Parser.logger
        @file_triples_path = nil
        @missing_imports = nil
        @reasoning = true
      end

      def setup_environment
        if @output_repo.nil? or Utils::FileHelpers.exists_and_file(@output_repo)
          raise RepositoryFoldersError, "Output repository folder are files in the system `#{@output_repo}`"
        end
        if @input_file.nil? or (not File.exist?(@input_file))
          raise InputFileNotFoundError, "#{@input_file} not found."
        end
        if @master_file.nil? and Utils::FileHelpers.zip?(@input_file)
          raise MasterFileMissingException , "Master file not provided and input is zipped archive."
        end
        if (not Dir.exist?(@output_repo))
          begin
            FileUtils.mkdir_p(@output_repo)
          rescue SystemCallError
            raise MkdirException, "Output folder #{@output_repo} folder cannot be created."
          end
        end
      end

      def disable_reasoner
        @reasoning = false
      end

      def call_owlapi_java_command
        options = []
        if not @input_file.nil?
          if @master_file.nil?
            options << "-m #{Shellwords.escape(@input_file.to_s)}" #if no master file the input repo is a unique file.
          else
            options << "-i #{Shellwords.escape(@input_file.to_s)}"
          end
        end
        if not @master_file.nil?
          options << "-m #{Shellwords.escape(@master_file.to_s)}"
        end
        if not @output_repo.nil?
          options << "-o #{Shellwords.escape(@output_repo.to_s)}"
        end
        options << "-r #{@reasoning ? "true" : "false"}"

        if options.length == 0
          raise ArgumentError, "Cannot call java OWLAPI command without options."
        end
        options = options.join ' '
        errors_log = File.join([@output_repo, "errors.log"])
        if File.exist? errors_log
          File.delete errors_log
        end
        command_call = "java -DentityExpansionLimit=1500000 -Xmx10240M -jar #{@owlapi_wrapper_jar_path} #{options}"
        @logger.info("Java call [#{command_call}]")
        stdout,stderr,status = Open3.capture3(command_call)
        if not status.success?
          @logger.error("OWLAPI java error in parse")
          @logger.error(stderr)
          @logger.error(stdout)
          raise Parser::OWLAPIParserException, "OWLAPI java command exited with #{status.exitstatus}. Check parser logs."
        else
          @logger.info("OWLAPI java parse finished OK.")
          @logger.info(stderr)
          @logger.info(stdout)
        end
        if not File.exist?(File.join([@output_repo, "owlapi.xrdf"]))
          raise Parser::OWLAPIParserException, "OWLAPI java command exited with #{status.exitstatus}. " +\
          "Output file #{File.join([@output_repo, "owlapi.xrdf"])} cannot be found."
        else
          @file_triples_path = File.join([@output_repo, "owlapi.xrdf"])
          @logger.info("Output size #{File.stat(@file_triples_path).size} in `#{@file_triples_path}`")
        end
        @missing_imports = []
        if File.exist? errors_log
          ferrors = File.open(errors_log,"r")
          lines = ferrors.read().split("\n")
          lines.each_index do |i|
            if lines[i].include? "OWL_IMPORT_MISSING"
              @missing_imports << lines[i+1].gsub("Message: ","")
            end
          end
          ferrors.close()
        end
        return [@file_triples_path, @missing_imports]
      end

      def file_triples_path
        @file_triples_path
      end

      def parse
        setup_environment
        call_owlapi_java_command
        if @file_triples_path.nil?
          raise RDFFileNotGeneratedException, "Triple file nil"
        elsif not File.exist?(@file_triples_path)
          raise RDFFileNotGeneratedException, "Triple file not found in #{@file_triples_path}"
        end
        return @file_triples_path, @missing_imports
      end
    end
  end
end

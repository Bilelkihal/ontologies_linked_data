require 'net/ftp'
require 'net/http'
require 'uri'
require 'open-uri'
require 'cgi'
require 'benchmark'

module LinkedData
  module Models

    class OntologySubmission < LinkedData::Models::Base

      FILES_TO_DELETE = ['labels.ttl', 'mappings.ttl', 'obsolete.ttl', 'owlapi.xrdf', 'errors.log']

      # The key is the property used by omv, the value is an array of properties mapped to the key omv property
      # (make sure the prefix is well defined in extract_mapped_array_metadata and extract_mapped_single_metadata SPARQL queries)
      # TODO: will disappear when attributes will be fully used
      OMV_ARRAY_METADATA = {"endorsedBy" => [],
                            "naturalLanguage" => ["dcterms:language"],
                            "designedForOntologyTask" => [],
                            "hasContributor" => ["dcterms:contributor"],
                            "hasCreator" => ["dcterms:creator"],
                            "hasDomain" => [],
                            "usedImports" => [],
                            "keywords" => [],
                            "knownUsage" => []}

      OMV_SINGLE_METADATA = {"documentation" => [],
                             "description" => ["dcterms:description"],
                             "hasFormalityLevel" => [],
                             "isOfType" => [],
                             "usedOntologyEngineeringTool" => [],
                             "usedOntologyEngineeringMethodology" => [],
                             "usedKnowledgeRepresentationParadigm" => [],
                             "notes" => []}

      model :ontology_submission, name_with: lambda { |s| submission_id_generator(s) }
      attribute :submissionId, enforce: [:integer, :existence]

      # Configurable properties for processing
      attribute :prefLabelProperty, enforce: [:uri]
      attribute :definitionProperty, enforce: [:uri]
      attribute :synonymProperty, enforce: [:uri]
      attribute :authorProperty, enforce: [:uri]
      attribute :classType, enforce: [:uri]
      attribute :hierarchyProperty, enforce: [:uri]
      attribute :obsoleteProperty, enforce: [:uri]
      attribute :obsoleteParent, enforce: [:uri]
      attribute :hasOntologyLanguage, namespace: :omv, enforce: [:existence, :ontology_format]

      # Ontology metadata
      attribute :homepage, namespace: :omv, extractedMetadata: true, metadataMappings: ["foaf:homepage", "cc:attributionURL", "mod:homepage", "doap:blog"] # TODO: change default attribute name ATTENTION NAMESPACE PAS VRAIMENT BON
      attribute :publication, namespace: :omv, extractedMetadata: true, metadataMappings: ["omv:reference", "dct:bibliographicCitation", "foaf:isPrimaryTopicOf", "schema:citation", "cito:isCitedBy", "bibo:isReferencedBy"] # TODO: change default attribute name
      attribute :URI, namespace: :omv #TODO: attention, attribute particulier. Je le récupère proprement via OWLAPI. le définir direct comme ça sans mappings ? Attention, Il a été passé en majuscule
      attribute :naturalLanguage, namespace: :omv, enforce: [:list], extractedMetadata: true, metadataMappings: ["dc:language", "dct:language", "doap:language"]
      attribute :documentation, namespace: :omv, extractedMetadata: true, metadataMappings: ["rdfs:seeAlso", "foaf:page", "vann:usageNote", "mod:document", "dcat:landingPage", "doap:wiki"]
      attribute :version, namespace: :omv, extractedMetadata: true, metadataMappings: ["owl:versionInfo", "mod:version", "doap:release"] # TODO: attention c'est déjà géré (mal) par BioPortal (le virer pour faire plus propre)
      attribute :description, namespace: :omv, extractedMetadata: true, metadataMappings: ["rdfs:comment", "dc:description", "dct:description", "doap:description"]
      attribute :status, namespace: :omv, extractedMetadata: true, metadataMappings: ["adms:status"] # Pas de limitation ici, mais seulement 4 possibilité dans l'UI (alpha, beta, production, retired)
      attribute :contact, enforce: [:existence, :contact, :list]  # Careful its special

      attribute :creationDate, namespace: :omv, enforce: [:date_time], default: lambda { |record| DateTime.now } # Attention c'est créé automatiquement ça, quand la submission est créée
      attribute :released, enforce: [:date_time, :existence], extractedMetadata: true, metadataMappings: ["omv:creationDate", "dc:date", "prov:generatedAtTime", "mod:creationDate", "doap:created"]   # date de release de l'ontologie par ses développeurs

      # Complementary omv metadata
      attribute :modificationDate, namespace: :omv, enforce: [:date_time], extractedMetadata: true, metadataMappings: ["dct:modified"]  # Va falloir faire en sorte de pouvoir extraire la date
      attribute :numberOfAxioms, namespace: :omv, enforce: [:integer], extractedMetadata: true, metadataMappings: ["mod:noOfAxioms"]  # TODO: extract les integers
      attribute :keyClasses, namespace: :omv, enforce: [:uri, :list], extractedMetadata: true, metadataMappings: ["foaf:primaryTopic", "void:exampleResource"]
      attribute :keywords, namespace: :omv, enforce: [:list], extractedMetadata: true, metadataMappings: ["mod:keyword", "dcat:keyword"] # Attention particulier, ça peut être un simple string avec des virgules
      attribute :knownUsage, namespace: :omv, enforce: [:list], extractedMetadata: true
      attribute :notes, namespace: :omv, extractedMetadata: true, metadataMappings: ["adms:versionNotes"]
      attribute :conformsToKnowledgeRepresentationParadigm, namespace: :omv, extractedMetadata: true, metadataMappings: ["mod:KnowledgeRepresentationFormalism"]
      attribute :hasContributor, namespace: :omv, enforce: [:list], extractedMetadata: true, metadataMappings: ["dc:contributor", "dct:contributor", "doap:helper"]
      attribute :hasCreator, namespace: :omv, enforce: [:list], extractedMetadata: true, metadataMappings: ["dc:creator", "dct:creator", "foaf:maker", "prov:wasAttributedTo", "doap:maintainer"]
      attribute :designedForOntologyTask, namespace: :omv, enforce: [:list], extractedMetadata: true, metadataMappings: []
      attribute :endorsedBy, namespace: :omv, enforce: [:list], extractedMetadata: true, metadataMappings: ["mod:endorsedBy"]
      attribute :hasDomain, namespace: :omv, enforce: [:list], extractedMetadata: true, metadataMappings: ["dc:subject", "dct:subject", "foaf:topic", "dcat:theme"]
      attribute :hasFormalityLevel, namespace: :omv, extractedMetadata: true, metadataMappings: ["mod:formalityLevel"]
      attribute :hasLicense, namespace: :omv, enforce: [:list], extractedMetadata: true, metadataMappings: ["dc:rights", "dct:license", "cc:license"]
      attribute :hasOntologySyntax, namespace: :omv, extractedMetadata: true, metadataMappings: ["mod:syntax", "dct:format"]
      attribute :isOfType, namespace: :omv, extractedMetadata: true, metadataMappings: ["dc:type", "dct:type"]
      attribute :usedOntologyEngineeringMethodology, namespace: :omv, enforce: [:list], extractedMetadata: true, metadataMappings: ["mod:methodologyUsed", "adms:representationTechnique"]
      attribute :usedOntologyEngineeringTool, namespace: :omv, extractedMetadata: true, metadataMappings: ["mod:toolUsed"]
      attribute :useImports, namespace: :omv, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: ["owl:imports", "door:imports", "void:vocabulary", "voaf:extends", "dct:requires"]
      attribute :hasPriorVersion, namespace: :omv, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: ["owl:priorVersion", "dct:isVersionOf", "door:priorVersion", "prov:wasDerivedFrom", "adms:prev"]
      attribute :isBackwardCompatibleWith, namespace: :omv, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: ["owl:backwardCompatibleWith", "door:backwardCompatibleWith"]
      attribute :isIncompatibleWith, namespace: :omv, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: ["owl:incompatibleWith", "door:owlIncompatibleWith"]
      attribute :numberOfAxioms, namespace: :omv, enforce: [:integer], extractedMetadata: true, metadataMappings: ["mod:noOfAxioms", "void:triples"]

      # New metadata to BioPortal
      attribute :hostedBy, enforce: [:list, :uri]
      attribute :deprecated, namespace: :owl, enforce: [:boolean], extractedMetadata: true, metadataMappings: []
      attribute :csvDump, enforce: [:uri]

      # New metadata from DOOR
      attribute :ontologyRelatedTo, namespace: :door, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: ["dc:relation", "dct:relation", "voaf:reliesOn"]
      attribute :comesFromTheSameDomain, namespace: :door, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: []
      attribute :similarTo, namespace: :door, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: ["voaf:similar"]
      attribute :isAlignedTo, namespace: :door, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: ["voaf:hasEquivalencesWith"]
      attribute :explanationEvolution, namespace: :door, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: ["voaf:specializes", "prov:specializationOf"]
      attribute :hasDisparateModelling, namespace: :door, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: []

      # New metadata from SKOS
      attribute :hiddenLabel, namespace: :skos, extractedMetadata: true, metadataMappings: []

      # New metadata from DC terms
      attribute :coverage, namespace: :dc, extractedMetadata: true, metadataMappings: ["dct:coverage"]
      attribute :publisher, namespace: :dc, extractedMetadata: true, metadataMappings: ["dct:publisher", "adms:schemaAgency"]
      attribute :identifier, namespace: :dc, extractedMetadata: true, metadataMappings: ["dct:identifier", "skos:notation", "adms:identifier"]
      attribute :source, namespace: :dc, enforce: [:list], extractedMetadata: true, metadataMappings: ["dct:source", "prov:wasInfluencedBy"]
      attribute :abstract, namespace: :dct, extractedMetadata: true, metadataMappings: []
      attribute :alternative, namespace: :dct, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: ["skos:altLabel"]
      attribute :hasPart, namespace: :dct, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: []
      attribute :isFormatOf, namespace: :dct, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: []
      attribute :audience, namespace: :dct, extractedMetadata: true, metadataMappings: ["doap:audience"]
      attribute :valid, namespace: :dct, enforce: [:date_time], extractedMetadata: true, metadataMappings: ["prov:invaliatedAtTime", "schema:endDate"]

      # New metadata from VOID
      attribute :sparqlEndpoint, namespace: :void, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: []
      attribute :entities, namespace: :void, enforce: [:integer], extractedMetadata: true, metadataMappings: []
      attribute :dataDump, namespace: :void, enforce: [:uri], extractedMetadata: true, metadataMappings: ["doap:download-mirror"]
      attribute :openSearchDescription, namespace: :void, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: ["doap:service-endpoint"]
      attribute :uriLookupEndpoint, namespace: :void, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: []

      # New metadata from foaf
      attribute :depiction, namespace: :foaf, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: ["doap:screenshots"]
      attribute :logo, namespace: :foaf, enforce: [:uri], extractedMetadata: true, metadataMappings: []
      attribute :fundedBy, namespace: :foaf, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: ["mod:sponsoredBy"]

      # New metadata from MOD
      attribute :competencyQuestion, namespace: :mod, extractedMetadata: true, metadataMappings: []

      # New metadata from VOAF
      attribute :usedBy, namespace: :voaf, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: []  # Range : Ontology
      attribute :metadataVoc, namespace: :voaf, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: ["mod:vocabularyUsed", "adms:supportedSchema"]
      attribute :generalizes, namespace: :voaf, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: [] # Ontology range
      attribute :hasDisjunctionsWith, namespace: :voaf, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: [] # Ontology range
      attribute :toDoList, namespace: :voaf, enforce: [:list], extractedMetadata: true, metadataMappings: []

      # New metadata from VANN
      attribute :example, namespace: :vann, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: []
      attribute :preferredNamespaceUri, namespace: :vann, extractedMetadata: true, metadataMappings: ["void:uriSpace"]
      attribute :preferredNamespacePrefix, namespace: :vann, extractedMetadata: true, metadataMappings: []

      # New metadata from CC
      attribute :morePermissions, namespace: :cc, extractedMetadata: true, metadataMappings: []
      attribute :useGuidelines, namespace: :cc, extractedMetadata: true, metadataMappings: []

      # New metadata from PROV
      attribute :wasGeneratedBy, namespace: :prov, extractedMetadata: true, metadataMappings: []
      attribute :wasInvalidatedBy, namespace: :prov, extractedMetadata: true, metadataMappings: []

      # New metadata from ADMS and DOAP
      attribute :translation, namespace: :adms, enforce: [:list, :uri], extractedMetadata: true, metadataMappings: []
      attribute :repository, namespace: :doap, enforce: [:uri], extractedMetadata: true, metadataMappings: []
      #attribute :bug-database, namespace: :doap, enforce: [:uri], extractedMetadata: true, metadataMappings: []  le tiret ne marche pas dans les attributs
      #attribute :mailing-list, namespace: :doap, enforce: [:uri], extractedMetadata: true, metadataMappings: []

      # Internal values for parsing - not definitive
      attribute :uploadFilePath
      attribute :diffFilePath
      attribute :masterFileName
      attribute :submissionStatus, enforce: [:submission_status, :list], default: lambda { |record| [LinkedData::Models::SubmissionStatus.find("UPLOADED").first] }
      attribute :missingImports, enforce: [:list]

      # URI for pulling ontology
      attribute :pullLocation, enforce: [:uri]

      # Link to ontology
      attribute :ontology, enforce: [:existence, :ontology]

      # Link to metrics
      attribute :metrics, enforce: [:metrics]

      # Hypermedia settings
      embed :contact, :ontology
      embed_values :submissionStatus => [:code], :hasOntologyLanguage => [:acronym]
      serialize_default :contact, :ontology, :hasOntologyLanguage, :released, :creationDate, :homepage,
                        :publication, :documentation, :version, :description, :naturalLanguage, :status, :submissionId

      # Links
      links_load :submissionId, ontology: [:acronym]
      link_to LinkedData::Hypermedia::Link.new("metrics", lambda {|s| "ontologies/#{s.ontology.acronym}/submissions/#{s.submissionId}/metrics"}, self.type_uri)
              LinkedData::Hypermedia::Link.new("download", lambda {|s| "ontologies/#{s.ontology.acronym}/submissions/#{s.submissionId}/download"}, self.type_uri)

      # HTTP Cache settings
      cache_timeout 3600
      cache_segment_instance lambda {|sub| segment_instance(sub)}
      cache_segment_keys [:ontology_submission]
      cache_load ontology: [:acronym]

      # Access control
      read_restriction_based_on lambda {|sub| sub.ontology}
      access_control_load ontology: [:administeredBy, :acl, :viewingRestriction]

      def self.segment_instance(sub)
        sub.bring(:ontology) unless sub.loaded_attributes.include?(:ontology)
        sub.ontology.bring(:acronym) unless sub.ontology.loaded_attributes.include?(:acronym)
        [sub.ontology.acronym] rescue []
      end

      def self.submission_id_generator(ss)
        if !ss.ontology.loaded_attributes.include?(:acronym)
          ss.ontology.bring(:acronym)
        end
        if ss.ontology.acronym.nil?
          raise ArgumentError, "Submission cannot be saved if ontology does not have acronym"
        end
        return RDF::URI.new(
          "#{(Goo.id_prefix)}ontologies/#{CGI.escape(ss.ontology.acronym.to_s)}/submissions/#{ss.submissionId.to_s}"
        )
      end

      def self.copy_file_repository(acronym, submissionId, src, filename = nil)
        path_to_repo = File.join([LinkedData.settings.repository_folder, acronym.to_s, submissionId.to_s])
        name = filename || File.basename(File.new(src).path)
        # THIS LOGGER IS JUST FOR DEBUG - remove after NCBO-795 is closed
        logger = Logger.new(Dir.pwd + "/create_permissions.log")
        if not Dir.exist? path_to_repo
          FileUtils.mkdir_p path_to_repo
          logger.debug("Dir created #{path_to_repo} | #{"%o" % File.stat(path_to_repo).mode} | umask: #{File.umask}") # NCBO-795
        end
        dst = File.join([path_to_repo, name])
        FileUtils.copy(src, dst)
        logger.debug("File created #{dst} | #{"%o" % File.stat(dst).mode} | umask: #{File.umask}") # NCBO-795
        if not File.exist? dst
          raise Exception, "Unable to copy #{src} to #{dst}"
        end
        return dst
      end

      def valid?
        valid_result = super
        return false unless valid_result
        sc = self.sanity_check
        return valid_result && sc
      end

      def sanity_check
        self.bring(:ontology) if self.bring?(:ontology)
        self.ontology.bring(:summaryOnly) if self.ontology.bring?(:summaryOnly)
        self.bring(:uploadFilePath) if self.bring?(:uploadFilePath)
        self.bring(:pullLocation) if self.bring?(:pullLocation)
        self.bring(:masterFileName) if self.bring?(:masterFileName)
        self.bring(:submissionStatus) if self.bring?(:submissionStatus)

        if (self.submissionStatus)
          self.submissionStatus.each do |st|
            st.bring(:code) if st.bring?(:code)
          end
        end

        if self.ontology.summaryOnly || self.archived?
          return true
        elsif self.uploadFilePath.nil? && self.pullLocation.nil?
          self.errors[:uploadFilePath] = ["In non-summary only submissions a data file or url must be provided."]
          return false
        elsif self.pullLocation
          self.errors[:pullLocation] = ["File at #{self.pullLocation.to_s} does not exist"]
          if self.uploadFilePath.nil?
            return remote_file_exists?(self.pullLocation.to_s)
          end
          return true
        end

        zip = LinkedData::Utils::FileHelpers.zip?(self.uploadFilePath)
        files =  LinkedData::Utils::FileHelpers.files_from_zip(self.uploadFilePath) if zip
        if not zip and self.masterFileName.nil?
          return true
        elsif zip and files.length == 1
          self.masterFileName = files.first
          return true
        elsif zip && self.masterFileName.nil? && LinkedData::Utils::FileHelpers.automaster?(self.uploadFilePath, self.hasOntologyLanguage.file_extension)
          self.masterFileName = LinkedData::Utils::FileHelpers.automaster(self.uploadFilePath, self.hasOntologyLanguage.file_extension)
          return true
        elsif zip and self.masterFileName.nil?
          #zip and masterFileName not set. The user has to choose.
          if self.errors[:uploadFilePath].nil?
            self.errors[:uploadFilePath] = []
          end

          #check for duplicated names
          repeated_names =  LinkedData::Utils::FileHelpers.repeated_names_in_file_list(files)
          if repeated_names.length > 0
            names = repeated_names.keys.to_s
            self.errors[:uploadFilePath] <<
            "Zip file contains file names (#{names}) in more than one folder."
            return false
          end

          #error message with options to choose from.
          self.errors[:uploadFilePath] << {
            :message => "Zip file detected, choose the master file.", :options => files }
          return false

        elsif zip and not self.masterFileName.nil?
          #if zip and the user chose a file then we make sure the file is in the list.
          files =  LinkedData::Utils::FileHelpers.files_from_zip(self.uploadFilePath)
          if not files.include? self.masterFileName
            if self.errors[:uploadFilePath].nil?
              self.errors[:uploadFilePath] = []
              self.errors[:uploadFilePath] << {
                :message =>
              "The selected file `#{self.masterFileName}` is not included in the zip file",
                :options => files }
            end
          end
        end
        return true
      end

      def data_folder
        bring(:ontology) if bring?(:ontology)
        self.ontology.bring(:acronym) if self.ontology.bring?(:acronym)
        bring(:submissionId) if bring?(:submissionId)
        return File.join(LinkedData.settings.repository_folder,
                         self.ontology.acronym.to_s,
                         self.submissionId.to_s)
      end

      def zip_folder
        return File.join([self.data_folder, "unzipped"])
      end

      def csv_path
        return File.join(self.data_folder, self.ontology.acronym.to_s + ".csv.gz")
      end

      def rdf_path
        return File.join(self.data_folder, "owlapi.xrdf")
      end

      def parsing_log_path
        return File.join(self.data_folder, 'parsing.log')
      end

      def unzip_submission(logger)
        zip = LinkedData::Utils::FileHelpers.zip?(self.uploadFilePath)
        zip_dst = nil

        if zip
          zip_dst = self.zip_folder

          if Dir.exist? zip_dst
            FileUtils.rm_r [zip_dst]
          end
          FileUtils.mkdir_p zip_dst
          extracted = LinkedData::Utils::FileHelpers.unzip(self.uploadFilePath, zip_dst)

          # Set master file name automatically if there is only one file
          if extracted.length == 1 && self.masterFileName.nil?
            self.masterFileName = extracted.first.name
            self.save
          end

          logger.info("Files extracted from zip #{extracted}")
          logger.flush
        end
        return zip_dst
      end

      def delete_old_submission_files
        path_to_repo = data_folder
        submission_files = FILES_TO_DELETE.map { |f| File.join(path_to_repo, f) }
        submission_files.push(csv_path)
        submission_files.push(parsing_log_path) unless parsing_log_path.nil?
        FileUtils.rm(submission_files, force: true)
      end

      # accepts another submission in 'older' (it should be an 'older' ontology version)
      def diff(logger, older)
        begin
          self.bring_remaining
          self.bring(:diffFilePath)
          self.bring(:uploadFilePath)
          older.bring(:uploadFilePath)
          LinkedData::Diff.logger = logger
          bubastis = LinkedData::Diff::BubastisDiffCommand.new(
              File.expand_path(older.uploadFilePath),
              File.expand_path(self.uploadFilePath)
          )
          self.diffFilePath = bubastis.diff
          self.save
          logger.info("Bubastis diff generated successfully for #{self.id}")
          logger.flush
        rescue Exception => e
          logger.error("Bubastis diff for #{self.id} failed - #{e.class}: #{e.message}")
          logger.flush
          raise e
        end
      end

      def generate_rdf(logger, file_path,reasoning=true)
        mime_type = nil

        if self.hasOntologyLanguage.umls?
          zip = LinkedData::Utils::FileHelpers.zip?(self.uploadFilePath)
          file_name = zip ?
              File.join(File.expand_path(self.data_folder.to_s), self.masterFileName) : self.uploadFilePath.to_s
          triples_file_path = File.expand_path(file_name)
          logger.info("Using UMLS turtle file, skipping OWLAPI parse")
          logger.flush
          mime_type = LinkedData::MediaTypes.media_type_from_base(LinkedData::MediaTypes::TURTLE)
        else
          output_rdf = File.join(File.dirname(file_path), "owlapi.xrdf")
          if File.exist?(output_rdf)
            logger.info("deleting old owlapi.xrdf ..")
            deleted = FileUtils.rm(output_rdf)
            if deleted.length > 0
              logger.info("deleted")
            else
              logger.info("error deleting owlapi.rdf")
            end
          end
          owlapi = LinkedData::Parser::OWLAPICommand.new(
              File.expand_path(file_path),
              File.expand_path(self.data_folder.to_s),
              master_file: self.masterFileName)
          if !reasoning
            owlapi.disable_reasoner
          end
          triples_file_path, missing_imports = owlapi.parse

          if missing_imports && missing_imports.length > 0
            self.missingImports = missing_imports
            missing_imports.each do |imp|
              logger.info("OWL_IMPORT_MISSING: #{imp}")
            end
          else
            self.missingImports = nil
          end
          logger.flush
        end
        delete_and_append(triples_file_path, logger, mime_type)
        begin
          # Extract metadata directly from the ontology
          extract_all_metadata(logger)
          logger.info("Additional metadata extracted.")
        rescue => e
          logger.error("Error while extracting additional metadata: #{e}")
        end
        # TODO: Remove this extraction of version, when extract metadata will be good
        version_info = extract_version()
        if version_info
          self.version = version_info
        end
      end

      # Extract additional metadata about the ontology
      # First it extracts the main metadata, then the mapped metadata
      def extract_all_metadata(logger)
        ontology_uri = extract_ontology_uri()

        # Retrieve ontology URI attribute directly with OWLAPI
        self.URI = ontology_uri
        if self.hostedBy.nil?
          self.hostedBy = [ RDF::URI.new("http://#{LinkedData.settings.ui_host}") ]
        end
        #self.csvDump = RDF::URI.new("http://data.stageportal.lirmm.fr/ontologies/BIOREFINERY/download?download_format=csv")
        self.csvDump = RDF::URI.new("#{self.ontology.id.to_s}/download?download_format=csv")

        # go through all OntologySubmission attributes. Returns symbols
        LinkedData::Models::OntologySubmission.attributes(:all).each do |attr|
          # for attribute with the :extractedMetadata setting on
          if (LinkedData::Models::OntologySubmission.attribute_settings(attr)[:extractedMetadata])
            # a boolean to check if a value that should be single have already been extracted
            single_extracted = false

            if !LinkedData::Models::OntologySubmission.attribute_settings(attr)[:namespace].nil?
              property_to_extract = LinkedData::Models::OntologySubmission.attribute_settings(attr)[:namespace].to_s + ":" + attr.to_s
              hash_results = extract_each_metadata(ontology_uri, attr, property_to_extract, logger)

              if (LinkedData::Models::OntologySubmission.attribute_settings(attr)[:enforce].include?(:list))
                # Add the retrieved value(s) to the attribute if the attribute take a list of objects
                metadata_values = self.send(attr.to_s).dup
                hash_results.each do |k,v|
                  metadata_values.push(v)
                end
                self.send("#{attr.to_s}=", metadata_values)
              else
                # If multiple value for a metadata that should have a single value: taking one value randomly (the first in the hash)
                hash_results.each do |k,v|
                  single_extracted = true
                  self.send("#{attr.to_s}=", v)
                  break
                end
              end
            end

            if !LinkedData::Models::OntologySubmission.attribute_settings(attr)[:metadataMappings].nil?

              LinkedData::Models::OntologySubmission.attribute_settings(attr)[:metadataMappings].each do |mapping|

                if single_extracted == true
                  # if an attribute with only one possible object as already been extracted
                  break
                end
                hash_mapping_results = extract_each_metadata(ontology_uri, attr, mapping.to_s, logger)

                if (LinkedData::Models::OntologySubmission.attribute_settings(attr)[:enforce].include?(:list))
                  # Add the retrieved value(s) to the attribute if the attribute take a list of objects
                  metadata_values = self.send(attr.to_s).dup
                  hash_mapping_results.each do |k,v|
                    metadata_values.push(v)
                  end
                  self.send("#{attr.to_s}=", metadata_values)
                else
                  # If multiple value for a metadata that should have a single value: taking one value randomly (the first in the hash)
                  hash_mapping_results.each do |k,v|
                    self.send("#{attr.to_s}=", v)
                    break
                  end
                end
              end
            end
          end
        end

      end


      # Return a hash with the best literal value for an URI
      # it selects the literal according to their language: no language > english > french > other languages
      def select_metadata_literal(metadata_uri, metadata_literal, hash)
        if metadata_literal.is_a?(RDF::Literal)
          if hash.has_key?(metadata_uri)
            if metadata_literal.has_language?
              if !hash[metadata_uri].has_language?
                return hash
              else
                if metadata_literal.language == :en || metadata_literal.language == :eng
                  # Take the value with english language over other languages
                  hash[metadata_uri] = metadata_literal
                  return hash
                elsif metadata_literal.language == :fr || metadata_literal.language == :fre
                  # If no english, take french
                  if hash[metadata_uri].language == :en || hash[metadata_uri].language == :eng
                    return hash
                  else
                    hash[metadata_uri] = metadata_literal
                    return hash
                  end
                else
                  return hash
                end
              end
            else
              # Take the value with no language in priority (considered as a default)
              hash[metadata_uri] = metadata_literal
              return hash
            end
          else
            hash[metadata_uri] = metadata_literal
            return hash
          end
        end
      end


      # A function to extract additional metadata
      # Take the literal data if the property is pointing to a literal
      # If pointing to an URI: first it takes the "omv:name" of the object pointed by the property, if nil it takes the "rdfs:label".
      # If not found it check for "omv:firstName + omv:lastName" (for "omv:Person") of this object. And to finish it takes the "URI"
      # The hash_results contains the metadataUri (objet pointed on by the metadata property) with the value we are using from it
      def extract_each_metadata(ontology_uri, attr, prop_to_extract, logger)

        query_metadata = <<eos 

SELECT DISTINCT ?extractedObject ?omvname ?omvfirstname ?omvlastname ?rdfslabel
FROM #{self.id.to_ntriples}
WHERE {
  <#{ontology_uri}> #{prop_to_extract} ?extractedObject .
  OPTIONAL { ?extractedObject omv:name ?omvname } .
  OPTIONAL { ?extractedObject omv:firstName ?omvfirstname } .
  OPTIONAL { ?extractedObject omv:lastName ?omvlastname } .
  OPTIONAL { ?extractedObject rdfs:label ?rdfslabel } .
}
eos
        Goo.namespaces.each do |prefix,uri|
          query_metadata = "PREFIX #{prefix}: <#{uri}>\n" + query_metadata
        end

        #logger.info(query_metadata)
        # This hash will contain the "literal" metadata for each object (uri or literal) pointed by the metadata predicate
        hash_results = {}
        Goo.sparql_query_client.query(query_metadata).each_solution do |sol|

          if LinkedData::Models::OntologySubmission.attribute_settings(attr)[:enforce].include?(:uri)
            # If the attr is enforced as URI then it directly takes the URI
            if sol[:extractedObject].is_a?(RDF::URI)
              hash_results[sol[:extractedObject]] = sol[:extractedObject]
            end

          elsif LinkedData::Models::OntologySubmission.attribute_settings(attr)[:enforce].include?(:date_time)
            begin
              hash_results[sol[:extractedObject]] = DateTime.iso8601(sol[:extractedObject].to_s)
            rescue => e
              logger.error("Impossible to extract DateTime metadata: #{e}")
            end

          elsif LinkedData::Models::OntologySubmission.attribute_settings(attr)[:enforce].include?(:integer)
            begin
              hash_results[sol[:extractedObject]] = sol[:extractedObject].to_s.to_i
            rescue => e
              logger.error("Impossible to extract integer metadata: #{e}")
            end

          else
            if sol[:extractedObject].is_a?(RDF::URI)
              # if the object is an URI but we are requesting a String
              # TODO: ATTENTION on veut pas forcément TOUT le temps recump omvname, etc... Voir si on change ce comportement
              if !sol[:omvname].nil?
                hash_results = select_metadata_literal(sol[:extractedObject],sol[:omvname], hash_results)
              elsif !sol[:rdfslabel].nil?
                hash_results = select_metadata_literal(sol[:extractedObject],sol[:rdfslabel], hash_results)
              elsif !sol[:omvfirstname].nil?
                hash_results = select_metadata_literal(sol[:extractedObject],sol[:omvfirstname], hash_results)
                # if first and last name are defined (for omv:Person)
                if !sol[:omvlastname].nil?
                  hash_results[sol[:extractedObject]] = hash_results[sol[:extractedObject]].to_s + " " + sol[:omvlastname].to_s
                end
              elsif !sol[:omvlastname].nil?
                # if only last name is defined
                hash_results = select_metadata_literal(sol[:extractedObject],sol[:omvlastname], hash_results)
              else
                hash_results[sol[:extractedObject]] = sol[:extractedObject].to_s
              end

            else
              # If this is directly a literal
              hash_results = select_metadata_literal(sol[:extractedObject],sol[:extractedObject], hash_results)
            end
          end
        end

        return hash_results
      end
      

      # Extract the ontology URI to use it to extract ontology metadata
      def extract_ontology_uri
        query_get_onto_uri = <<eos
SELECT DISTINCT ?uri
FROM #{self.id.to_ntriples}
WHERE {
<http://bioportal.bioontology.org/ontologies/versionSubject> <http://omv.ontoware.org/2005/05/ontology#URI> ?uri .
}
eos
        Goo.sparql_query_client.query(query_get_onto_uri).each_solution do |sol|
          return sol[:uri].to_s
        end
        return nil
      end


      def extract_version

        query_version_info = <<eos
SELECT ?versionInfo
FROM #{self.id.to_ntriples}
WHERE {
<http://bioportal.bioontology.org/ontologies/versionSubject>
 <http://www.w3.org/2002/07/owl#versionInfo> ?versionInfo .
}
eos
        Goo.sparql_query_client.query(query_version_info).each_solution do |sol|
          return sol[:versionInfo].to_s
        end
        return nil
      end

      def generate_missing_labels(logger, file_path)
        save_in_file = File.join(File.dirname(file_path), "labels.ttl")
        save_in_file_mappings = File.join(File.dirname(file_path), "mappings.ttl")
        property_triples = LinkedData::Utils::Triples.rdf_for_custom_properties(self)
        result = Goo.sparql_data_client.append_triples(
            self.id,
            property_triples,
            mime_type="application/x-turtle")
        count_classes = 0
        page = 1
        size = 2500
        fsave = File.open(save_in_file,"w")
        fsave.write(property_triples)
        paging = LinkedData::Models::Class.in(self).include(:prefLabel, :synonym, :label).page(page, size)

        begin #per page
          prefLabel = nil
          label_triples = []
          mapping_triples = []
          t0 = Time.now
          page_classes = paging.page(page,size).read_only.all
          t1 = Time.now
          logger.info(
            "#{page_classes.length} in page #{page} classes for "+
                  "#{self.id.to_ntriples} (#{t1 - t0} sec)." +
                  " Total pages #{page_classes.total_pages}.")
          logger.flush

          page_classes.each do |c|
            if c.prefLabel.nil?
              rdfs_labels = c.label

              if rdfs_labels && rdfs_labels.length > 1 && c.synonym.length > 0
                rdfs_labels = (Set.new(c.label) -  Set.new(c.synonym)).to_a.first
                if rdfs_labels.nil? || rdfs_labels.length == 0
                  rdfs_labels = c.label
                end
              end
              if rdfs_labels and not (rdfs_labels.instance_of?Array)
                rdfs_labels = [rdfs_labels]
              end
              label = nil

              if rdfs_labels && rdfs_labels.length > 0
                label = rdfs_labels[0]
              else
                label = LinkedData::Utils::Triples.last_iri_fragment c.id.to_s
              end
              label_triples << LinkedData::Utils::Triples.label_for_class_triple(
                  c.id, Goo.vocabulary(:metadata_def)[:prefLabel],label)
              prefLabel = label
            else
              prefLabel = c.prefLabel
            end
            if self.ontology.viewOf.nil?
              loomLabel = OntologySubmission.loom_transform_literal(prefLabel.to_s)
              if loomLabel.length > 2
                mapping_triples << LinkedData::Utils::Triples.loom_mapping_triple(
                  c.id, Goo.vocabulary(:metadata_def)[:mappingLoom], loomLabel)
              end
              mapping_triples << LinkedData::Utils::Triples.uri_mapping_triple(
                c.id, Goo.vocabulary(:metadata_def)[:mappingSameURI], c.id)
            end
            count_classes += 1
          end

          rest_mappings = LinkedData::Mappings
            .migrate_rest_mappings(self.ontology.acronym)
          mapping_triples.concat rest_mappings

          if (label_triples.length > 0)
            logger.info("Asserting #{label_triples.length} labels in " +
                        "#{self.id.to_ntriples}")
            logger.flush
            label_triples = label_triples.join "\n"
            fsave.write(label_triples)
            t0 = Time.now
            result = Goo.sparql_data_client.append_triples(
                self.id,
                label_triples,
                mime_type="application/x-turtle")
            t1 = Time.now
            logger.info("Labels asserted in #{t1 - t0} sec.")
            logger.flush
          else
            logger.info("No labels generated in page #{page_classes.total_pages}.")
            logger.flush
          end
          if (mapping_triples.length > 0)
            fsave_mappings = File.open(save_in_file_mappings,"w")
            logger.info("Asserting #{mapping_triples.length} mappings in " +
                        "#{self.id.to_ntriples}")
            logger.flush
            mapping_triples = mapping_triples.join "\n"
            fsave_mappings.write(mapping_triples)
            fsave_mappings.close()
            t0 = Time.now
            result = Goo.sparql_data_client.append_triples(
                self.id,
                mapping_triples,
                mime_type="application/x-turtle")
            t1 = Time.now
            logger.info("Mapping labels asserted in #{t1 - t0} sec.")
            logger.flush
          end
          page = page_classes.next? ? page + 1 : nil
        end while !page.nil?
        logger.info("end generate_missing_labels traversed #{count_classes} classes")
        logger.info("Saved generated labels in #{save_in_file}")
        fsave.close()
        logger.flush
      end

      def generate_obsolete_classes(logger, file_path)
        self.bring(:obsoleteProperty) if self.bring?(:obsoleteProperty)
        self.bring(:obsoleteParent) if self.bring?(:obsoleteParent)
        classes_deprecated = []
        if self.obsoleteProperty &&
          self.obsoleteProperty.to_s != "http://www.w3.org/2002/07/owl#deprecated"

          predicate_obsolete = RDF::URI.new(self.obsoleteProperty.to_s)
          query_obsolete_predicate = <<eos
SELECT ?class_id ?deprecated
FROM #{self.id.to_ntriples}
WHERE { ?class_id #{predicate_obsolete.to_ntriples} ?deprecated . }
eos
          Goo.sparql_query_client.query(query_obsolete_predicate).each_solution do |sol|
            unless sol[:deprecated].to_s == "false"
              classes_deprecated << sol[:class_id].to_s
            end
          end
          logger.info("Obsolete found #{classes_deprecated.length} for property #{self.obsoleteProperty.to_s}")
        end
        if self.obsoleteParent.nil?
          #try to find oboInOWL obsolete.
          obo_in_owl_obsolete_class = LinkedData::Models::Class
                                  .find(LinkedData::Utils::Triples.obo_in_owl_obsolete_uri)
                                  .in(self).first
          if obo_in_owl_obsolete_class
            self.obsoleteParent = LinkedData::Utils::Triples.obo_in_owl_obsolete_uri
          end
        end
        if self.obsoleteParent
          class_obsolete_parent = LinkedData::Models::Class
                                  .find(self.obsoleteParent)
                                  .in(self).first
          if class_obsolete_parent
            descendents_obsolete = class_obsolete_parent.descendants
            logger.info("Found #{descendents_obsolete.length} descendents of obsolete root #{self.obsoleteParent.to_s}")
            descendents_obsolete.each do |obs|
              classes_deprecated << obs.id
            end
          else
            logger.error("Submission #{self.id.to_s} obsoleteParent #{self.obsoleteParent.to_s} not found")
          end
        end
        if classes_deprecated.length > 0
          classes_deprecated.uniq!
          logger.info("Asserting owl:deprecated statement for #{classes_deprecated} classes")
          save_in_file = File.join(File.dirname(file_path), "obsolete.ttl")
          fsave = File.open(save_in_file,"w")
          classes_deprecated.each do |class_id|
            fsave.write(LinkedData::Utils::Triples.obselete_class_triple(class_id) + "\n")
          end
          fsave.close()
          result = Goo.sparql_data_client.append_triples_from_file(
                          self.id,
                          save_in_file,
                          mime_type="application/x-turtle")
        end
      end

      def add_submission_status(status)
        valid = status.is_a?(LinkedData::Models::SubmissionStatus)
        raise ArgumentError, "The status being added is not SubmissionStatus object" unless valid

        #archive removes the other status
        if status.archived?
          self.submissionStatus = [status]
          return self.submissionStatus
        end

        self.submissionStatus ||= []
        s = self.submissionStatus.dup

        if (status.error?)
          # remove the corresponding non_error status (if exists)
          non_error_status = status.get_non_error_status()
          s.reject! { |stat| stat.get_code_from_id() == non_error_status.get_code_from_id() } unless non_error_status.nil?
        else
          # remove the corresponding non_error status (if exists)
          error_status = status.get_error_status()
          s.reject! { |stat| stat.get_code_from_id() == error_status.get_code_from_id() } unless error_status.nil?
        end

        has_status = s.any? { |s| s.get_code_from_id() == status.get_code_from_id() }
        s << status unless has_status
        self.submissionStatus = s

      end

      def remove_submission_status(status)
        if (self.submissionStatus)
          valid = status.is_a?(LinkedData::Models::SubmissionStatus)
          raise ArgumentError, "The status being removed is not SubmissionStatus object" unless valid
          s = self.submissionStatus.dup

          # remove that status as well as the error status for the same status
          s.reject! { |stat|
            stat_code = stat.get_code_from_id()
            stat_code == status.get_code_from_id() ||
                stat_code == status.get_error_status().get_code_from_id()
          }
          self.submissionStatus = s
        end
      end

      def set_ready()
        ready_status = LinkedData::Models::SubmissionStatus.get_ready_status

        ready_status.each do |code|
          status = LinkedData::Models::SubmissionStatus.find(code).include(:code).first
          add_submission_status(status)
        end
      end

      # allows to optionally submit a list of statuses
      # that would define the "ready" state of this
      # submission in this context
      def ready?(options={})
        self.bring(:submissionStatus) if self.bring?(:submissionStatus)
        status = options[:status] || :ready
        status = status.is_a?(Array) ? status : [status]
        return true if status.include?(:any)
        return false unless self.submissionStatus

        if status.include? :ready
          return LinkedData::Models::SubmissionStatus.status_ready?(self.submissionStatus)
        else
          status.each do |x|
            return false if self.submissionStatus.select { |x1|
              x1.get_code_from_id() == x.to_s.upcase
            }.length == 0
          end
          return true
        end
      end

      def archived?
        return ready?(status: [:archived])
      end

      ########################################
      # Possible options with their defaults:
      #   process_rdf       = true
      #   index_search      = true
      #   index_commit      = true
      #   run_metrics       = true
      #   reasoning         = true
      #   diff              = true
      #   archive           = false
      #######################################
      def process_submission(logger, options={})
        # Wrap the whole process so we can email results
        begin
          process_rdf = options[:process_rdf] == false ? false : true
          index_search = options[:index_search] == false ? false : true
          index_commit = options[:index_commit] == false ? false : true
          run_metrics = options[:run_metrics] == false ? false : true
          reasoning = options[:reasoning] == false ? false : true
          diff = options[:diff] == false ? false : true
          archive = options[:archive] == true ? true : false

          self.bring_remaining
          self.ontology.bring_remaining

          logger.info("Starting to process #{self.ontology.acronym}/submissions/#{self.submissionId}")
          logger.flush
          LinkedData::Parser.logger = logger
          status = nil

          if archive
            self.submissionStatus = nil
            status = LinkedData::Models::SubmissionStatus.find("ARCHIVED").first
            add_submission_status(status)

            # Delete everything except for original ontology file.
            ontology.bring(:submissions)
            submissions = ontology.submissions
            unless submissions.nil?
              submissions.each { |s| s.bring(:submissionId) }
              submission = submissions.sort { |a,b| b.submissionId <=> a.submissionId }[0]
              # Don't perform deletion if this is the most recent submission.
              if (self.submissionId < submission.submissionId)
                delete_old_submission_files
              end
            end
          else
            if process_rdf
              # Remove processing status types before starting RDF parsing etc.
              self.submissionStatus = nil
              status = LinkedData::Models::SubmissionStatus.find("UPLOADED").first
              add_submission_status(status)
              self.save

              # Parse RDF
              file_path = nil
              begin
                if not self.valid?
                  error = "Submission is not valid, it cannot be processed. Check errors."
                  raise ArgumentError, error
                end
                if not self.uploadFilePath
                  error = "Submission is missing an ontology file, cannot parse."
                  raise ArgumentError, error
                end
                status = LinkedData::Models::SubmissionStatus.find("RDF").first
                remove_submission_status(status) #remove RDF status before starting
                zip_dst = unzip_submission(logger)
                file_path = zip_dst ? zip_dst.to_s : self.uploadFilePath.to_s
                generate_rdf(logger, file_path, reasoning=reasoning)
                add_submission_status(status)
                self.save
              rescue Exception => e
                logger.error("#{self.errors}")
                logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
                logger.flush
                add_submission_status(status.get_error_status)
                self.save
                # If RDF generation fails, no point of continuing
                raise e
              end

              status = LinkedData::Models::SubmissionStatus.find("RDF_LABELS").first
              begin
                generate_missing_labels(logger, file_path)
                add_submission_status(status)
                self.save
              rescue Exception => e
                logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
                logger.flush
                add_submission_status(status.get_error_status)
                self.save
                # if rdf label generation fails, no point of continuing
                raise e
              end

              status = LinkedData::Models::SubmissionStatus.find("OBSOLETE").first
              begin
                generate_obsolete_classes(logger, file_path)
                add_submission_status(status)
                self.save
              rescue Exception => e
                logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
                logger.flush
                add_submission_status(status.get_error_status)
                self.save
                # if obsolete fails the parsing fails
                raise e
              end
            end

            parsed = ready?(status: [:rdf, :rdf_labels])

            if index_search
              raise Exception, "The submission #{self.ontology.acronym}/submissions/#{self.submissionId} cannot be indexed because it has not been successfully parsed" unless parsed
              status = LinkedData::Models::SubmissionStatus.find("INDEXED").first
              begin
                index(logger, index_commit, false)
                add_submission_status(status)
              rescue Exception => e
                logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
                logger.flush
                add_submission_status(status.get_error_status)
                if File.file?(self.csv_path)
                  FileUtils.delete(self.csv_path)
                end
              ensure
                self.save
              end
            end

            if run_metrics
              raise Exception, "Metrics cannot be generated on the submission #{self.ontology.acronym}/submissions/#{self.submissionId} because it has not been successfully parsed" unless parsed
              status = LinkedData::Models::SubmissionStatus.find("METRICS").first
              begin
                process_metrics(logger)
                add_submission_status(status)
              rescue Exception => e
                logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
                logger.flush
                self.metrics = nil
                add_submission_status(status.get_error_status)
              ensure
                self.save
              end
            end

            if diff
              status = LinkedData::Models::SubmissionStatus.find("DIFF").first
              # Get previous submission from ontology.submissions
              self.ontology.bring(:submissions)
              submissions = self.ontology.submissions

              unless submissions.nil?
                submissions.each {|s| s.bring(:submissionId, :diffFilePath)}
                # Sort submissions in descending order of submissionId, extract last two submissions
                recent_submissions = submissions.sort {|a, b| b.submissionId <=> a.submissionId}[0..1]

                if recent_submissions.length > 1
                  # validate that the most recent submission is the current submission
                  if self.submissionId == recent_submissions.first.submissionId
                    prev = recent_submissions.last

                    # Ensure that prev is older than the current submission
                    if self.submissionId > prev.submissionId
                      # generate a diff
                      begin
                        self.diff(logger, prev)
                        add_submission_status(status)
                      rescue Exception => e
                        logger.error("#{e.class}: #{e.message}\n#{e.backtrace.join("\n\t")}")
                        logger.flush
                        add_submission_status(status.get_error_status)
                      ensure
                        self.save
                      end
                    end
                  end
                else
                  logger.info("Bubastis diff: no older submissions available for #{self.id}.")
                end
              else
                logger.info("Bubastis diff: no submissions available for #{self.id}.")
              end
            end
          end

          self.save
          logger.info("Submission processing of #{self.id} completed successfully")
          logger.flush
        ensure
          # make sure results get emailed
          begin
            LinkedData::Utils::Notifications.submission_processed(self)
          rescue Exception => e
            logger.info("Email sending failed: #{e.message}\n#{e.backtrace.join("\n\t")}"); logger.flush
          end
          return self
        end
      end

      def process_metrics(logger)
        metrics = LinkedData::Metrics.metrics_for_submission(self, logger)
        metrics.id = RDF::URI.new(self.id.to_s + "/metrics")
        exist_metrics = LinkedData::Models::Metric.find(metrics.id).first
        exist_metrics.delete if exist_metrics
        metrics.save
        self.metrics = metrics
        return self
      end

      def index(logger, commit = true, optimize = true)
        page = 1
        size = 500

        count_classes = 0
        time = Benchmark.realtime do
          self.bring(:ontology) if self.bring?(:ontology)
          logger.info("Indexing ontology: #{self.ontology.acronym}...")
          t0 = Time.now
          self.ontology.unindex(commit)
          logger.info("Removing ontology index (#{Time.now - t0}s)"); logger.flush

          paging = LinkedData::Models::Class.in(self).include(:unmapped)
                                  .page(page,size)

          writer = LinkedData::Utils::OntologyCSVWriter.new
          writer.open(self.ontology, self.csv_path)

          begin #per page
            t0 = Time.now
            page_classes = paging.page(page,size).all
            logger.info("Page #{page} of #{page_classes.total_pages} classes retrieved in #{Time.now - t0} sec.")
            t0 = Time.now
            page_classes.each do |c|
              LinkedData::Models::Class.map_attributes(c,paging.equivalent_predicates)
              writer.write_class(c)
            end
            logger.info("Page #{page} of #{page_classes.total_pages} attributes mapped in #{Time.now - t0} sec.")
            count_classes += page_classes.length
            t0 = Time.now

            LinkedData::Models::Class.indexBatch(page_classes)
            logger.info("Page #{page} of #{page_classes.total_pages} indexed solr in #{Time.now - t0} sec.")
            logger.info("Page #{page} of #{page_classes.total_pages} completed")
            logger.flush

            page = page_classes.next? ? page + 1 : nil
          end while !page.nil?

          writer.close

          # index provisional classes
          self.ontology.bring(:provisionalClasses) if self.ontology.bring?(:provisionalClasses)
          self.ontology.provisionalClasses.each { |pc| pc.index }

          if (commit)
            t0 = Time.now
            LinkedData::Models::Class.indexCommit()
            logger.info("Solr index commit in #{Time.now - t0} sec.")
          end
        end
        logger.info("Completed indexing ontology: #{self.ontology.acronym} in #{time} sec. #{count_classes} classes.")
        logger.flush

        if optimize
          logger.info("Optimizing index...")
          time = Benchmark.realtime do
            LinkedData::Models::Class.indexOptimize()
          end
          logger.info("Completed optimizing index in #{time} sec.")
        end
      end

      # Override delete to add removal from the search index
      #TODO: revise this with a better process
      def delete(*args)
        options = {}
        args.each {|e| options.merge!(e) if e.is_a?(Hash)}
        remove_index = options[:remove_index] ? true : false
        index_commit = options[:index_commit] == false ? false : true

        super(*args)
        self.ontology.unindex(index_commit)

        self.bring(:metrics) if self.bring?(:metrics)
        self.metrics.delete if self.metrics

        if remove_index
          # need to re-index the previous submission (if exists)
          self.ontology.bring(:submissions)
          if self.ontology.submissions.length > 0
            prev_sub = self.ontology.latest_submission()

            if prev_sub
              prev_sub.index(LinkedData::Parser.logger || Logger.new($stderr))
            end
          end
        end
      end

      def roots(extra_include=nil)

        unless self.loaded_attributes.include?(:hasOntologyLanguage)
          self.bring(:hasOntologyLanguage)
        end
        isSkos = false
        if self.hasOntologyLanguage
          isSkos = self.hasOntologyLanguage.skos?
        end

        classes = []
        if !isSkos
          owlThing = Goo.vocabulary(:owl)["Thing"]
          classes = LinkedData::Models::Class.where(parents: owlThing).in(self)
                                             .disable_rules
                                             .all
        else
          root_skos = <<eos
SELECT DISTINCT ?root WHERE {
GRAPH #{self.id.to_ntriples} {
  ?x #{RDF::SKOS[:hasTopConcept].to_ntriples} ?root .
}}
eos
          #needs to get cached
          class_ids = []
          Goo.sparql_query_client.query(root_skos, { :graphs => [self.id] }).each_solution do |s|
            class_ids << s[:root]
          end
          class_ids.each do |id|
            classes << LinkedData::Models::Class.find(id).in(self).disable_rules.first
          end
        end
        roots = []
        where = LinkedData::Models::Class.in(self)
                     .models(classes)
                     .include(:prefLabel, :definition, :synonym, :obsolete)
        if extra_include
          [:prefLabel, :definition, :synonym, :obsolete, :childrenCount].each do |x|
            extra_include.delete x
          end
        end
        load_children = []
        if extra_include
          load_children = extra_include.delete :children
          if load_children.nil?
            load_children = extra_include.select {
              |x| x.instance_of?(Hash) && x.include?(:children) }
            if load_children.length > 0
              extra_include = extra_include.select {
                |x| !(x.instance_of?(Hash) && x.include?(:children)) }
            end
          else
            load_children = [:children]
          end
          if extra_include.length > 0
            where.include(extra_include)
          end
        end
        where.all
        if load_children.length > 0
          LinkedData::Models::Class.partially_load_children(roots,99,self)
        end
        classes.each do |c|
          if !extra_include.nil? and extra_include.include?(:hasChildren)
            c.load_has_children
          end
          roots << c if (c.obsolete.nil?) || (c.obsolete == false)
        end
        return roots
      end

      def download_and_store_ontology_file
        file, filename = download_ontology_file
        file_location = self.class.copy_file_repository(self.ontology.acronym, self.submissionId, file, filename)
        self.uploadFilePath = file_location
        return file, filename
      end

      def remote_file_exists?(url)
        begin
          url = URI.parse(url)
          if url.kind_of?(URI::FTP)
            check = check_ftp_file(url)
          else
            check = check_http_file(url)
          end
        rescue Exception
          check = false
        end
        check
      end

      def download_ontology_file
        file, filename = LinkedData::Utils::FileHelpers.download_file(self.pullLocation.to_s)
        return file, filename
      end

      def delete_classes_graph
        Goo.sparql_data_client.delete_graph(self.id)
      end

      private

      def delete_and_append(triples_file_path, logger, mime_type = nil)
        Goo.sparql_data_client.delete_graph(self.id)
        Goo.sparql_data_client.put_triples(self.id, triples_file_path, mime_type)
        logger.info("Triples #{triples_file_path} appended in #{self.id.to_ntriples}")
        logger.flush
      end

      def check_http_file(url)
        session = Net::HTTP.new(url.host, url.port)
        session.use_ssl = true if url.port == 443
        session.start do |http|
          response_valid = http.head(url.request_uri).code.to_i < 400
          return response_valid
        end
      end

      def check_ftp_file(uri)
        ftp = Net::FTP.new(uri.host, uri.user, uri.password)
        ftp.login
        begin
          file_exists = ftp.size(uri.path) > 0
        rescue Exception => e
          # Check using another method
          path = uri.path.split("/")
          filename = path.pop
          path = path.join("/")
          ftp.chdir(path)
          files = ftp.dir
          # Dumb check, just see if the filename is somewhere in the list
          files.each { |file| return true if file.include?(filename) }
        end
        file_exists
      end

      def self.loom_transform_literal(lit)
        res = []
        lit.each_char do |c|
          if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
            res << c.downcase
          end
        end
        return res.join ''
      end

    end
  end
end

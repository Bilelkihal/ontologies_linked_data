module LinkedData
  module Models
    class ProvisionalClass < LinkedData::Models::Base
      model :provisional_class, name_with: lambda { |inst| uuid_uri_generator(inst) }

      attribute :label, enforce: [:existence]
      attribute :synonym, enforce: [:list]
      attribute :definition, enforce: [:list]
      attribute :subclassOf, enforce: [:uri]
      attribute :creator, enforce: [:existence, :user]
      attribute :created, enforce: [:date_time], :default => lambda { |record| DateTime.now }
      attribute :permanentId, enforce: [:uri]
      attribute :noteId, enforce: [:uri]
      attribute :ontology, enforce: [:ontology]

      search_options :index_id => lambda { |t| t.index_id },
                     :document => lambda { |t| t.index_doc }


      def index_id
        return nil unless self.ontology
        latest = self.ontology.latest_submission(status: :any)
        return nil unless latest
        "#{self.id.to_s}_#{self.ontology.acronym}_#{latest.submissionId}"
      end

      def index_doc
        return {} unless self.ontology
        latest = self.ontology.latest_submission(status: :any)
        return {} unless latest

        doc = {
          :resource_id => self.id.to_s,
          :prefLabel => self.label,
          :obsolete => false,
          :provisional => true,
          :submissionAcronym => self.ontology.acronym,
          :submissionId => latest.submissionId
        }

        all_attrs = self.to_hash
        std = [:id, :synonym, :definition]

        std.each do |att|
          cur_val = all_attrs[att]
          # don't store empty values
          next if cur_val.nil? || cur_val.empty?

          if (cur_val.is_a?(Array))
            doc[att] = []
            cur_val = cur_val.uniq
            cur_val.map { |val| doc[att] << (val.kind_of?(Goo::Base::Resource) ? val.id.to_s : val.to_s.strip) }
          else
            doc[att] = cur_val.to_s.strip
          end
        end

        doc
      end

      def index
        if index_id
          unindex
          super
          LinkedData::Models::Ontology.indexCommit
        end
      end

      def unindex
        if index_id
          query = "id:#{solr_escape(index_id)}"
          LinkedData::Models::Ontology.unindexByQuery(query)
          LinkedData::Models::Ontology.indexCommit
        end
      end

      def solr_escape(text)
        RSolr.solr_escape(text).gsub(/\s+/,"\\ ")
      end
    end
  end
end

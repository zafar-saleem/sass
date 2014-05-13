module Sass
  module Selector
    # A comma-separated sequence of selectors.
    class CommaSequence < AbstractSequence
      # The comma-separated selector sequences
      # represented by this class.
      #
      # @return [Array<Sequence>]
      attr_reader :members

      # @param seqs [Array<Sequence>] See \{#members}
      def initialize(seqs)
        @members = seqs
      end

      # Resolves the {Parent} selectors within this selector
      # by replacing them with the given parent selector,
      # handling commas appropriately.
      #
      # @param super_cseq [CommaSequence] The parent selector
      # @param implicit_parent [Boolean] Whether the the parent
      #   selector should automatically be prepended to the resolved
      #   selector if it contains no parent refs.
      # @return [CommaSequence] This selector, with parent references resolved
      # @raise [Sass::SyntaxError] If a parent selector is invalid
      def resolve_parent_refs(super_cseq, implicit_parent = true)
        if super_cseq.nil?
          if @members.any? do |sel|
               sel.members.any? do |sel_or_op|
                 sel_or_op.is_a?(SimpleSequence) &&
                   sel_or_op.members.any? {|ssel| ssel.is_a?(Parent)}
               end
             end
            raise Sass::SyntaxError.new(
              "Base-level rules cannot contain the parent-selector-referencing character '&'.")
          end
          return self
        end

        CommaSequence.new(Sass::Util.flatten_vertically(@members.map do |seq|
          seq.resolve_parent_refs(super_cseq, implicit_parent).members
        end))
      end

      # Non-destrucively extends this selector with the extensions specified in a hash
      # (which should come from {Sass::Tree::Visitors::Cssize}).
      #
      # @todo Link this to the reference documentation on `@extend`
      #   when such a thing exists.
      #
      # @param extends [Sass::Util::SubsetMap{Selector::Simple =>
      #                                       Sass::Tree::Visitors::Cssize::Extend}]
      #   The extensions to perform on this selector
      # @param parent_directives [Array<Sass::Tree::DirectiveNode>]
      #   The directives containing this selector.
      # @return [CommaSequence] A copy of this selector,
      #   with extensions made according to `extends`
      def do_extend(extends, parent_directives = [])
        CommaSequence.new(members.map do |seq|
          extended = seq.do_extend(extends, parent_directives)
          # First Law of Extend: the result of extending a selector should
          # always contain the base selector.
          #
          # See https://github.com/nex3/sass/issues/324.
          extended.unshift seq unless seq.has_placeholder? || extended.include?(seq)
          extended
        end.flatten)
      end

      # Populates a subset map that can then be used to extend
      # selectors. This registers an extension with this selector as
      # the extender and `extendee` as the extendee.
      #
      # @param extends [Sass::Util::SubsetMap{Selector::Simple =>
      #                                       Sass::Tree::Visitors::Cssize::Extend}]
      #   The subset map representing the extensions to perform.
      # @param extendee [CommaSequence] The selector being extended.
      # @param extend_node [Sass::Tree::ExtendNode]
      #   The node that caused this extension.
      # @param parent_directives [Array<Sass::Tree::DirectiveNode>]
      #   The parent directives containing `extend_node`.
      # @raise [Sass::SyntaxError] if this extension is invalid.
      def populate_extends(extends, extendee, extend_node = nil, parent_directives = [])
        extendee.members.each do |seq|
          if seq.members.size > 1
            raise Sass::SyntaxError.new("Can't extend #{seq}: can't extend nested selectors")
          end

          sseq = seq.members.first
          if !sseq.is_a?(Sass::Selector::SimpleSequence)
            raise Sass::SyntaxError.new("Can't extend #{seq}: invalid selector")
          elsif sseq.members.any? {|ss| ss.is_a?(Sass::Selector::Parent)}
            raise Sass::SyntaxError.new("Can't extend #{seq}: can't extend parent selectors")
          end

          sel = sseq.members
          members.each do |member|
            unless member.members.last.is_a?(Sass::Selector::SimpleSequence)
              raise Sass::SyntaxError.new("#{member} can't extend: invalid selector")
            end

            extends[sel] = Sass::Tree::Visitors::Cssize::Extend.new(
              member, sel, extend_node, parent_directives, :not_found)
          end
        end
      end

      # Returns a SassScript representation of this selector.
      #
      # @return [Sass::Script::Value::List]
      def to_sass_script
        Sass::Script::Value::List.new(members.map do |seq|
          Sass::Script::Value::List.new(seq.members.map do |component|
            Sass::Script::Value::String.new(component.to_s)
          end, :space)
        end, :comma)
      end

      # Returns a string representation of the sequence.
      # This is basically the selector string.
      #
      # @return [String]
      def inspect
        members.map {|m| m.inspect}.join(", ")
      end

      # @see AbstractSequence#to_s
      def to_s
        @members.join(", ").gsub("\n", "")
      end

      private

      def _hash
        members.hash
      end

      def _eql?(other)
        other.class == self.class && other.members.eql?(members)
      end
    end
  end
end

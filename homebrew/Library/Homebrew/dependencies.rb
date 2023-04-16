# typed: true
# frozen_string_literal: true

require "delegate"

# A collection of dependencies.
#
# @api private
class Dependencies < SimpleDelegator
  extend T::Sig

  def initialize(*args)
    super(args)
  end

  alias eql? ==

  def optional
    __getobj__.select(&:optional?)
  end

  def recommended
    __getobj__.select(&:recommended?)
  end

  def build
    __getobj__.select(&:build?)
  end

  def required
    __getobj__.select(&:required?)
  end

  def default
    build + required + recommended
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: #{__getobj__}>"
  end
end

# A collection of requirements.
#
# @api private
class Requirements < SimpleDelegator
  extend T::Sig

  def initialize(*args)
    super(Set.new(args))
  end

  def <<(other)
    if other.is_a?(Object) && other.is_a?(Comparable)
      __getobj__.grep(other.class) do |req|
        return self if req > other

        __getobj__.delete(req)
      end
    end
    super
    self
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: {#{__getobj__.to_a.join(", ")}}>"
  end
end

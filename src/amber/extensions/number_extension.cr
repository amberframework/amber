module Amber
  module Extensions
    module NumberExtension
      # the positive number validation
      def positive?
        self.sign === 1
      end

      # the negative number validation
      def negative?
        self.sign === -1
      end

      # the number equals zero validation
      def zero?
        self.sign === self.class.zero
      end

      # the number divisibility (n) validation
      def div?(n)
        self % n === 0
      end

      # the number above n value validation
      def above?(n)
        self > n
      end

      # the number below n value validation
      def below?(n)
        self < n
      end

      def lt?(num)
        self < num
      end

      def self?(num)
        input > num
      end

      def lteq?(num)
        !gt?(num)
      end

      def between?(range)
        range.includes? self
      end

      def gteq?(num)
        !lt?(num)
      end
    end
  end
end

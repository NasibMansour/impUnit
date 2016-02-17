/**
 * Test runner
 * @package ImpUnit
 */

// extend Promise for our needs
// don't do this at home
class Promise extends Promise {
  function isPending() {
    return this._state == 0;
  }
}

/**
 * Imp test runner
 */
class ImpUnitRunner {

  // options
  timeout = 2;
  readableOutput = true;
  stopOnFailure = false;
  session = null;

  // result
  tests = 0;
  assertions = 0;
  failures = 0;

  _testsGenerator = null;

  /**
   * Run tests
   */
  function run() {
    this._log(ImpUnitMessage(ImpUnitMessageTypes.sessionStart))
    this._testsGenerator = this._findTests();
    this._run();
  }

  /**
   * Log message
   * @param {ImpUnitMessage} message
   * @private
   */
  function _log(message) {
    // set session id
    message.session = this.session;

    if (this.readableOutput) {
      server.log(message.toString() /* use custom conversion method to avoid stack resizing limitations on metamethods */)
    } else {
      server.log(message.toJSON());
    }
  }

  /**
   * Loog for test cases/test functions
   * @returns {generator}
   * @private
   */
  function _findTests() {

    // iterate through the
    foreach (rootKey, rootValue in getroottable()) {

      if (type(rootValue) == "class" && rootValue.getbase() == ImpTestCase) {

        // create instance of the test class
        local testCase = rootValue();

        // log setUp() execution
        this._log(ImpUnitMessage(ImpUnitMessageTypes.testStart, rootKey + "::setUp()"));

        // yield setUp method
        yield {
          "case" : testCase,
          "method" : testCase.setUp.bindenv(testCase)
        };

        // iterate through members of test class
        foreach (memberKey, memberValue in rootValue) {
          // look for test* methods
          if (memberKey.len() >= 4 && memberKey.slice(0, 4) == "test") {
            // log test method execution
            this._log(ImpUnitMessage(ImpUnitMessageTypes.testStart, rootKey + "::" + memberKey + "()"));

            this.tests++;

            // yield test method
            yield {
              "case" : testCase,
              "method" : memberValue.bindenv(testCase)
            };
          }

        }

        // log tearDown() execution
        this._log(ImpUnitMessage(ImpUnitMessageTypes.testStart, rootKey + "::tearDown()"));

        // yield tearDown method
        yield {
          "case" : testCase,
          "method" : testCase.tearDown.bindenv(testCase)
        };
      }

    }

    // we're done
    return null;
  }

  /**
   * We're done
   * @private
   */
  function _finish() {
    // log result message
    this._log(ImpUnitMessage(ImpUnitMessageTypes.sessionResult, {
      tests = this.tests,
      assertions = this.assertions,
      failures = this.failures
    }));
  }

  /**
   * Called when test method is finished
   * @param {bool} success
   * @param {*} result - resolution/rejection argument
   * @param {integer} assertions - # of assettions made
   * @private
   */
  function _done(success, result, assertions = 0) {
      if (!success) {
        // log failure
        this.failures++;
        this._log(ImpUnitMessage(ImpUnitMessageTypes.testFail, result));
      } else {
        // log test method success
        this._log(ImpUnitMessage(ImpUnitMessageTypes.testOk, result));
      }

      // update assertions number
      this.assertions += assertions;

      // next
      if (!success && this.stopOnFailure) {
        this._finish();
      } else {
        this._run.bindenv(this)();
      }
  }

  function _now() {
    return "hardware" in getroottable()
      ? hardware.millis().tofloat() / 1000
      : time();
  }

  /**
   * Run tests
   * @private
   */
  function _run() {

    local test = resume this._testsGenerator;

    if (test) {

      // do GC before each run
      collectgarbage();

      test.assertions <- test["case"].assertions;
      test.result <- null;

      // record start time
      test.startedAt <- this._now();

      // run test method
      try {
        test.result = test.method();
      } catch (e) {
        // store sync test info
        test.error <- e;
      }

      // detect if test is async
      test.async <- test.result instanceof Promise;

      if (test.async) {

        // set the timeout timer

        test.timedOut <- false;

        test.timerId <- imp.wakeup(this.timeout, function () {
          if (test.result.isPending()) {
            test.timedOut = true;

            // update assertions counter to ignore assertions afrer the timeout
            test.assertions = test["case"].assertions;

            this._done(false, "Test timed out after " + this.timeout + "s");
          }
        }.bindenv(this));

        // handle result

        test.result

          // we're fine
          .then(function (message) {
            test.message <- message;
          })

          // we're screwed
          .fail(function (error) {
            test.error <- error;
          })

          // anyways...
          .finally(function(e) {

            // cancel timeout detection
            if (test.timerId) {
              imp.cancelwakeup(test.timerId);
              test.timerId = null;
            }

            if (!test.timedOut) {
              if ("error" in test) {
                this._done(false /* failure */, test.error, test["case"].assertions - test.assertions);
              } else {
                this._done(true /* success */, test.message, test["case"].assertions - test.assertions);
              }
            }

          }.bindenv(this));

      } else {
        // check timeout

        local testDuration = this._now() - test.startedAt;

        if (testDuration > this.timeout) {
          test.error <- "Test took " + testDuration + "s, longer than timeout of " + this.timeout + "s"
        }

        // test was sync
        if ("error" in test) {
          this._done(false /* failure */, test.error, test["case"].assertions - test.assertions);
        } else {
          this._done(true /* success */, test.result, test["case"].assertions - test.assertions);
        }
      }

    } else {
      this._finish();
    }

  }

}

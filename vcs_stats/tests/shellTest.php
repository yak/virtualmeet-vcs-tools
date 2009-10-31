<?php

require_once 'PHPUnit/Framework.php';
require_once '../includes/shell.php';


/**
 * Test class for Shell
 *
 * @package    vcs-stats
 * @author     Kristoffer Lindqvist <kris@tsampa.org>
 * @copyright  2009 Kristoffer Lindqvist
 * @license    http://www.opensource.org/licenses/mit-license.php MIT license
 */
class shellTest extends PHPUnit_Framework_TestCase {

	public function test_exec_echo() {

		$stdout = Shell::exec('echo "testing 123";', $exit_code, $stderr);

		$this->assertType('string', $stdout);
		$this->assertEquals('testing 123', $stdout);

		$this->assertEquals(0, $exit_code, 'Exit code should be integer zero for a successful ls');

		$this->assertType('string', $stderr);
		$this->assertEquals('', $stderr);

	}

	public function test_exec_syntax_error() {

		$stdout = Shell::exec('for (( i = 0; i  4; i++ )); do echo $i; done;', $exit_code, $stderr);

		$this->assertType('string', $stdout);
		$this->assertEquals('', $stdout);

		$this->assertEquals(1, $exit_code, 'A BASH syntax error should have exit code 1');

		$this->assertRegExp('/syntax error/', $stderr);
	}

}

<?php


/**
 * Shell wrapper
 *
 * @package    vcs-stats
 * @author     Kristoffer Lindqvist <kris@tsampa.org>
 * @copyright  2009 Kristoffer Lindqvist
 * @license    http://www.opensource.org/licenses/mit-license.php MIT license
 */
class Shell {

	/**
	 * Execute a shell command
	 *
	 * @param	string		$command: command to execute
	 * @param	integer		$exit_code: exit code of $command
	 * @param	string		$stderr: stderr output of $command
	 * @return	string		stdout output of $command
	 */
	public static function exec($command, &$exit_code, &$stderr) {

		// punch out the exit code, stderr and stdout separated by |-#-|-#-|
		$output = explode("|-#-|-#-|", shell_exec('{ stdout=$(' . $command . ') ; } 2>&1; echo "|-#-|-#-|${?}|-#-|-#-|"; printf "%s" "$stdout";'));

		if (count($output) != 3) {
			throw new Exception('Shell::exec command seems to be broken, got: ' . print_r($output, true));
		}

		$stderr = trim($output[0]);
		$exit_code = (int)$output[1];

		return trim($output[2]);
	}

}

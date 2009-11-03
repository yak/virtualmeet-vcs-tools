<?php

require_once 'PHPUnit/Framework.php';
require_once '../includes/vcs_git.php';

/**
 * Test class for VCS_Git.
 *
 * Operates against the real binary, so suitable for checking whether it works
 * against the system version before deploying.
 *
 * @package    vcs-stats
 * @author     Kristoffer Lindqvist <kris@tsampa.org>
 * @copyright  2009 Kristoffer Lindqvist
 * @license    http://www.opensource.org/licenses/mit-license.php MIT license
 */
class vcs_gitTest extends PHPUnit_Framework_TestCase {

	/**
	 * Where the repo to test again is created
	 */
	const TEST_REPO_PATH = '/tmp/gittest_938ejhfg3847j';


	/**
	 * Where to find Git
	 */
	const GIT_BINARY = '/usr/bin/env git';


	/**
	 * Test repo author name
	 */
	const TEST_NAME = 'John the Tester';


	/**
	 * Test repo author e-mail
	 */
	const TEST_EMAIL = 'megatester@localhost';


    /**
     * @var VCS_Git
     */
    protected $repo;


    /**
     * Sets up the fixture, eg. a small Git repo to test against
	 * that is recreated for each test.
     */
    protected function setUp() {
		ob_start();
?>
		/usr/bin/env mkdir <?=self::TEST_REPO_PATH ?> &&
		cd <?=self::TEST_REPO_PATH ?> &&
		<?=self::GIT_BINARY ?> init &&
		<?=self::GIT_BINARY ?> config user.name '<?=self::TEST_NAME ?>' &&
		<?=self::GIT_BINARY ?> config user.email <?=self::TEST_EMAIL ?> &&
		echo 'hello world' > test.txt &&
		<?=self::GIT_BINARY ?> add . &&
		<?=self::GIT_BINARY ?> commit -m "First commit" &&
		echo 'hello world we have changed' > test.txt &&
		echo 'Git is to juice as fish is to cattle' > git.txt &&
		<?=self::GIT_BINARY ?> add . &&
		<?=self::GIT_BINARY ?> commit -m "Second commit" &&
		echo 'hello world' > test.txt &&
		<?=self::GIT_BINARY ?> add . &&
		<?=self::GIT_BINARY ?> commit -m "Third commit"
<?php
		shell_exec( ob_get_clean() );

		$this->repo = new VCS_Git(self::TEST_REPO_PATH);
    }


	public function test_get_repository_path() {
		$this->assertEquals(self::TEST_REPO_PATH, $this->repo->get_repository_path(), 'Repository path is not what we passed');
	}


	public function test_head_commit_drilldown() {
		$git_formatted_author = self::TEST_NAME . ' <' . self::TEST_EMAIL . '>';

		$head_commit = $this->repo->get_head_commit();
		$this->assertType('Commit', $head_commit, 'The received HEAD commit is not an object of type Commit');
		$this->assertEquals($git_formatted_author, $head_commit->get_author(), 'Author fails for HEAD commit');
		$this->assertEquals('Third commit', $head_commit->get_commit_message());

		$second_commit = $this->repo->get_parent_of_commit($head_commit->get_revision());
		$this->assertType('Commit', $second_commit, 'The parent of HEAD commit is not an object of type Commit');
		$this->assertEquals($git_formatted_author, $second_commit->get_author(), 'Author fails for parent of HEAD commit');
		$this->assertEquals('Second commit', $second_commit->get_commit_message());
		$this->assertNotEquals($head_commit->get_revision(), $second_commit->get_revision(), 'The head commit hash matches that of the second commit hash');

		$third_commit = $this->repo->get_parent_of_commit($second_commit->get_revision());
		$this->assertEquals('First commit', $third_commit->get_commit_message());

		// hmmm... when at the first commit, should probably return something more intelligent such as NULL...
		$this->setExpectedException('GitException');
		$null_commit = $this->repo->get_parent_of_commit($third_commit->get_revision());
	}


	public function test_get_commit_by_revision() {
		$head_commit = $this->repo->get_head_commit();

		$this->assertEquals($head_commit->get_revision(), $this->repo->get_commit($head_commit->get_revision())->get_revision(), 'Failed getting the head commit back by commit hash');
	}


	public function test_branching_head() {
		$this->assertEquals('master', $this->repo->get_current_branch(), 'New repository, should be on master');

		$test_branch = 'my_little_test_branch';
		$head_commit = $this->repo->get_head_commit();

		$this->repo->create_branch($test_branch, $head_commit->get_revision());
		$this->repo->switch_to_branch($test_branch);
		$this->assertEquals($test_branch, $this->repo->get_current_branch(), 'Should have switched to ' . $test_branch);

		$test_branch_head_commit = $this->repo->get_head_commit();
		$this->assertEquals($head_commit, $test_branch_head_commit, 'We branched off HEAD, but the new branch head commit is not an identical copy of the HEAD head');

		$this->repo->switch_to_branch('master');
		$this->assertEquals('master', $this->repo->get_current_branch(), 'Switching back to master from branch failed');
		
		$this->repo->delete_branch($test_branch);

		$this->setExpectedException('GitException');
		$this->repo->switch_to_branch($test_branch);
	}


	public function test_cannot_delete_branch_one_is_on() {
		$test_branch = 'branched';
		$head_commit = $this->repo->get_head_commit();

		$this->repo->create_branch($test_branch, $head_commit->get_revision());
		$this->repo->switch_to_branch($test_branch);

		$this->setExpectedException('GitException');
		$this->repo->delete_branch($test_branch);
	}


	public function test_get_commit_count() {
		$this->assertEquals(3, $this->repo->get_commit_count(), 'Should have three commits');

		$test_branch = 'branched-again';
		$second_commit = $this->repo->get_parent_of_commit( $this->repo->get_head_commit()->get_revision() );

		$this->repo->create_branch($test_branch, $second_commit->get_revision());
		$this->assertEquals(3, $this->repo->get_commit_count(), 'Creating a second branch messes up the commit count');

		$this->repo->switch_to_branch($test_branch);
		$this->assertEquals(2, $this->repo->get_commit_count(), 'Branched off the second commit, commit count should be 2');
	}


    protected function tearDown() {
		shell_exec('rm -rf ' . self::TEST_REPO_PATH);
    }
}

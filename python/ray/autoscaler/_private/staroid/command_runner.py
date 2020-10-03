import os
from typing import Dict
from ray.autoscaler._private.command_runner import KubernetesCommandRunner


class StaroidCommandRunner(KubernetesCommandRunner):
    def __init__(self,
                 log_prefix,
                 namespace,
                 node_id,
                 auth_config,
                 process_runner,
                 kube_api_server=None):

        super(StaroidCommandRunner, self).__init__(
            log_prefix, namespace, node_id, auth_config, process_runner)

        if kube_api_server is not None:
            self.kubectl.extend(["--server", kube_api_server])
            os.environ["KUBE_API_SERVER"] = kube_api_server

    def _rewrite_target_home_dir(self, target):
        # Staroid forces containers to run non-root permission. Ray docker
        # image does not have a support for non-root user at the moment.
        # Use /tmp/ray as a home directory until docker image supports
        # non-root user.

        if target.startswith("~/"):
            return "/home/ray" + target[1:]
        return target

    def run(
            self,
            cmd=None,
            timeout=120,
            exit_on_fail=False,
            port_forward=None,
            with_output=False,
            environment_variables: Dict[str, object] = None,
            run_env="auto",  # Unused argument.
            ssh_options_override_ssh_key="",  # Unused argument.
            shutdown_after_run=False,
    ):
        try:
            return super().run(
                cmd,
                timeout,
                exit_on_fail,
                port_forward,
                with_output,
                environment_variables,
                run_env,
                ssh_options_override_ssh_key,
                shutdown_after_run
            )
        except BaseException as e:
            err_msg = str(e)

            # When multi node type, while head node container is creating,
            # translate exception message to more meaningful
            # Command 'kubectl -n crv-3009-109-5-944-1633-0-3010 --server http://localhost:53208 exec -it ray-headxmn64 -- bash --login -c -i 'true && source ~/.bashrc && export OMP_NUM_THREADS=1 PYTHONWARNINGS=ignore && (uptime)'' returned non-zero exit status 1.
            # 2020-10-03 11:53:31,574	INFO command_runner.py:165 -- NodeUpdater: ray-headxmn64: Running kubectl -n crv-3009-109-5-944-1633-0-3010 --server http://localhost:53208 exec -it ray-headxmn64 -- bash --login -c -i 'true && source ~/.bashrc && export OMP_NUM_THREADS=1 PYTHONWARNINGS=ignore && (uptime)'
            # error: unable to upgrade connection: container not found ("ray-node")
            if "container not found" in err_msg:
                raise BaseException("Container creating ...")

            # When node is provisioning
            if "does not have a host assigned" in err_msg:
                raise BaseException("Node provisioning ...")

            raise e

    def run_rsync_up(self, source, target, options=None):
        target = self._rewrite_target_home_dir(target)
        super().run_rsync_up(source, target, options)

    def run_rsync_down(self, source, target, options=None):
        target = self._rewrite_target_home_dir(target)
        super().run_rsync_down(source, target, options)

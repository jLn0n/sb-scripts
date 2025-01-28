const fs = require("fs");
const path = require("path");
const child_proc = require("child_process");

module.exports = function(github, context, core) {
	const upload_scripts = (script_dir, output_dirs, gist_id) => {
		const files = {}

		for (let output_dir of output_dirs) {
			files[path.basename(output_dir)] = {
				content: fs.readFileSync(output_dir).toString("utf-8"),
			}
		}

		github.rest.gists.update({
			gist_id: gist_id,
			description: `${script_dir} (https://github.com/${context.repo.owner}/${context.repo.repo}/tree/${context.sha}) - processed`,
			files: files,
			headers: {
				'X-GitHub-Api-Version': '2022-11-28'
			}
		})
	}

	const process_script_dir = (script_dir) => {
		const output_dirs = [];
		let scripts_name;

		const config_file_dir = path.join(script_dir, "config.json");
		if (!fs.existsSync(config_file_dir)) {
			console.log(`No config.json exists in directory: '${script_dir}'`)
			return;
		}

		const config_data = JSON.parse(fs.readFileSync(config_file_dir, 'utf8')) || {};
		scripts_name = config_data.name;

		if (typeof scripts_name !== "string") {
			console.log(`Name not provided on '${config_file_dir}', skipping...`);
			return;
		}

		console.log(`Processing scripts '${scripts_name}' on directory: '${script_dir}'`);

		if (typeof config_data.darklua_config !== "string") {
			console.log("Darklua config file not specified (or not string), skipping...");
			return;
		}
		if (config_data.process_files.length < 1) {
			console.log("There are no files to process, skipping...");
			return;
		}

		const full_darklua_config_dir = path.join(script_dir, config_data.darklua_config);
		if (!fs.existsSync(full_darklua_config_dir)) {
			console.log("Darklua config file not found, skipping...")
			return;
		}

		let _process_count = 0

		for (let file_dir of config_data.process_files) {
			const full_file_dir = path.join(script_dir, file_dir);
			if (!fs.existsSync(full_file_dir)) {
				console.log(`File '${file_dir}' from directory '${script_dir}' not found, skipping...`)
				continue;
			}

			const file_outdir = path.resolve("_output", scripts_name, file_dir);
			const command = `./darklua process ${full_file_dir} ${file_outdir} -c ${full_darklua_config_dir}`;

			try {
				child_proc.execSync(command)

				_process_count += 1;
				console.log(`Darklua processing of '${path.join(path.basename(script_dir), file_dir)}' succeeded, file is now saved at '${file_outdir}'`);
				output_dirs.push(file_outdir)
			} catch (cmd_err) {
				console.error(`Darklua errored with file '${file_dir}':`, cmd_err);
			}
		}

		console.log(`[${_process_count}/${config_data.process_files.length}] files processed.`);

		if (typeof config_data.gist_id === "string") {
			if (_process_count === config_data.process_files.length) {
				console.log("Gist id found & all requested files got processed successfully! Uploading...")
				upload_scripts(path.join(path.basename(script_dir), scripts_name), output_dirs, config_data.gist_id)
			} else {
				console.warn("Gist id exist, but all requested files didn't got processed successfully. Skipping...")
			}
		}
		return scripts_name, output_dirs;
	}

	const scripts_dir = path.resolve("scripts");
	for (let dir of fs.readdirSync(scripts_dir)) {
		process_script_dir(path.join(scripts_dir, dir));
	}
};

const fs = require("fs");
const path = require("path");
const child_proc = require("child_process");

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

	if (fs.existsSync(full_darklua_config_dir)) {
		let process_count = 0

		for (let file_dir of config_data.process_files) {
			const full_file_dir = path.join(script_dir, file_dir);
			if (!fs.existsSync(full_file_dir)) {
				console.log(`File '${file_dir}' from directory '${script_dir}' not found, skipping...`)
				continue;
			}

			const output_dir = path.resolve("_output", scripts_name, file_dir);
			const command = `./darklua process ${full_file_dir} ${output_dir} -c ${full_darklua_config_dir}`;

			child_proc.exec(command, (cmd_err, _stdout, _stderr) => {
				if (cmd_err) {
					console.error(`Darklua errored with file '${file_dir}':`, cmd_err);
					return
				}

				process_count += 1;
				console.log(`Darklua processing succeed, file is now saved at '${output_dir}'`);
				output_dirs.push(output_dir)
			});
		}

		console.log(`[${process_count}/${config_data.process_files.length}] files processed.`);
	} else {
		console.log("Darklua config file not found, skipping...")
		return;
	}
	return scripts_name, output_dirs;
}

module.exports = function(github, context, core) {
	const _output = []
	const scripts_dir = path.resolve("scripts");

	for (let dir of fs.readdirSync(scripts_dir)) {
		const [scripts_name, output_dirs] = process_script_dir(path.join(scripts_dir, dir));
		if (typeof scripts_name !== "string") {
			continue;
		}
	
		_output = _output.concat(output_dirs);
	}

	return JSON.stringify(_output);
};

let iconv = require("iconv-lite");
let fs = require("fs");

(async () => {
	function test(name, value, expect) {
		if (value === expect) {
			console.log("测试点 " + name + " 通过");
		} else {
			console.log("测试点 " + name + " 错误: ");
			console.log("  " + JSON.stringify(value) + " 不等于 " + JSON.stringify(expect));
		}
	}

	function pathWrite() {
		let st = instance.exports.pathStart.value / 4;
		let pl = instance.exports.pathLength.value;
		for (let i = 0; i < pl; i++) {
			let dt = memory[st + i];
			console.log(dt >> 16, dt & 0xffff);
		}
	}

	function pathAns(mapX, mapY, x1, y1, x2, y2, memory) {
		let dist = [];
		for (let i = 0; i < mapX * mapY; i++) {
			dist.push(Infinity);
		}
		dist[y1 * mapX + x1] = 0;
		let cycle = [x1, y1];
		while (cycle.length > 0) {
			let x = cycle[0];
			let y = cycle[1];
			let d = dist[y * mapX + x] + 1;
			//console.log("cyc",x,y);
			if (x === x2 && y === y2) {
				return d;
			}
			cycle.splice(0, 2);
			let z = [-1, 0, -1, 1, 0, 1, 1, 1, 1, 0, 1, -1, 0, -1, -1, -1];
			for (let a = 0; a < 16; a += 2) {
				let x0 = x + z[a];
				let y0 = y + z[a + 1];
				//console.log("fech",x0,y0);
				//console.log(memory[y*mapX+x]);
				if (y0 >= 0 && y0 < mapY && x0 >= 0 && x0 < mapX && memory[y * mapX + x] === 0) {
					let d0 = dist[y0 * mapX + x0];
					if (d0 > d) {
						dist[y0 * mapX + x0] = d;
						cycle.push(x0);
						cycle.push(y0);
					}
				}
			}
		}
		return -1;
	}

	let wabt = await (require("wabt")());
	// let module = wabt.readWasm(fs.readFileSync("main.wasm"), { readDebugNames: true});
	let wast = fs.readFileSync("main.wast").toString();
	let transfer = iconv.encode(wast, "ascii");
	let module, result;
	try {
		module = wabt.parseWat("main.wast", transfer, {});
		module.validate();
		result = module.toBinary({
			log: false,
			relocatable: true,
			write_debug_names: true
		});
		console.log(result.log);
	} catch (e) {
		console.log(e.message);
		process.exit(1);
	}
	let bin = result.buffer;
	module.destroy();
	fs.writeFileSync("main.wasm", bin);

	let wmodule = await WebAssembly.compile(bin);
	let instance;
	let memory;
	let wimport = {
		debug: {
			log: function(x) {
				console.log(x);
			},
			tell: function(x, y) {
				console.log(x + " ->");
				for (let i = 0; i < y / 4; i++) {
					let str = "";
					for (let j = i * 4; j < (i + 1) * 4; j++) {
						let out = "";
						let puz = memory[i / 4 + j];
						for (let k = 0; k < 8; k++) {
							out = "0123456789abcdef" [puz & 0xF] + out;
							puz >>= 4;
						}
						str += "0x" + out + " ";
					}
					console.log(str);
				}
			},
			inspect: function(x1, y1, x2, y2, path) {
				let mapX = instance.exports.mapX.value;
				let mapY = instance.exports.mapY.value;
				let mapStart = instance.exports.mapStart.value / 4;
				let diStart = instance.exports.diStart.value / 4;
				let fnStart = instance.exports.fnStart.value / 4;
				let gnStart = instance.exports.gnStart.value / 4;
				//console.log("map");
				//console.log(mapStart,diStart,fnStart,gnStart);
				//console.log(memory);
				for (let y = 0; y < mapY; y++) {
					let str = "";
					for (let x = 0; x < mapX; x++) {
						str += memory[mapStart + y * mapX + x] === 1 ? "##" : "::";
					}
					console.log(str);
				}
				console.log("di");
				for (let y = 0; y < mapY; y++) {
					let str = "";
					for (let x = 0; x < mapX; x++) {
						str += (memory[fnStart + y * mapX + x] === 0xffffffff ?
							"??" :
							"↖↑↗←⊙→↙↓↘" [memory[diStart + y * mapX + x]] + " "
						);
					}
					console.log(str);
				}
				console.log("fn");
				for (let y = 0; y < mapY; y++) {
					let str = "";
					for (let x = 0; x < mapX; x++) {
						str += (
							memory[fnStart + y * mapX + x] === 0xffffffff ?
							"??" :
							("  " + memory[fnStart + y * mapX + x]).slice(-2));
					}
					console.log(str);
				}
				console.log("gn");
				for (let y = 0; y < mapY; y++) {
					let str = "";
					for (let x = 0; x < mapX; x++) {
						str += (
							memory[gnStart + y * mapX + x] === 0xffffffff ?
							"??" :
							("  " + memory[gnStart + y * mapX + x]).slice(-2));
					}
					console.log(str);
				}
				if (arguments.length !== 0) {
					console.log("path");
					let disp = [];
					for (let y = 0; y < mapY; y++) {
						disp.push([]);
						for (let x = 0; x < mapX; x++) {
							disp[y].push(
								memory[mapStart + y * mapX + x] === 0 ? "::" : "##"
							);
						}
					}
					//console.log(mapX,mapY,path);
					for (let i = 0; i < path.length; i += 2) {
						disp[path[i]][path[i + 1]] = "[]";
					}
					disp[y1][x1] = "<>";
					disp[y2][x2] = "()";
					for (let y = 0; y < mapY; y++) {
						console.log(disp[y].join(""));
					}
				}
			}
		}
	};

	// 测试 内存拓展
	if (false) {
		instance = await WebAssembly.instantiate(wmodule, wimport);
		memory = new Uint32Array(instance.exports.memory.buffer);
		test("内存 1", instance.exports.getPage(), 1);
		test(2, instance.exports.growSize(1), 1);
		test(3, instance.exports.getPage(), 1);
		test(4, instance.exports.growSize(65536), 1);
		test(5, instance.exports.getPage(), 1);
		test(6, instance.exports.growSize(65537), 1);
		test(7, instance.exports.getPage(), 2);
		test(8, instance.exports.growSize(365 * 65536), 1);
		test(9, instance.exports.getPage(), 365);
		test(10, instance.exports.growSize(362 * 65536), 1);
		test(11, instance.exports.getPage(), 365);
		test(12, instance.exports.growSize(100 * 1024 * 1024), 1);
		test(13, instance.exports.getPage(), 100 * 1024 * 1024 / 65536);
		test(14, instance.exports.growSize(100 * 1024 * 1024 + 1), 0); // 超出预先设定的 100M 上限
		test(15, instance.exports.getPage(), 100 * 1024 * 1024 / 65536);
	}

	// 小根堆测试
	if (false) {
		instance = await WebAssembly.instantiate(wmodule, wimport);
		memory = new Uint32Array(instance.exports.memory.buffer);
		test("小根堆 1", instance.exports.PQadd(0, 0, 1, 2, 3), undefined);
		test(2, memory[0], 1);
		test(3, memory[1], 2);
		test(4, memory[2], 3);
		instance.exports.PQadd(16, 0, 1, 1, 1);
		instance.exports.PQadd(16, 1, 2, 2, 2);
		instance.exports.PQadd(16, 2, 3, 3, 3);
		// wimport.debug.tell();
		let pos;
		pos = instance.exports.PQpick(16, 3);
		test(5, memory[pos / 4 + 0], 1);
		test(6, memory[pos / 4 + 1], 1);
		test(7, memory[pos / 4 + 2], 1);
		// wimport.debug.tell();
		pos = instance.exports.PQpick(16, 2);
		test(8, memory[pos / 4 + 0], 2);
		test(9, memory[pos / 4 + 1], 2);
		test(10, memory[pos / 4 + 2], 2);
		// wimport.debug.tell();
		pos = instance.exports.PQpick(16, 1);
		test(11, memory[pos / 4 + 0], 3);
		test(12, memory[pos / 4 + 1], 3);
		test(13, memory[pos / 4 + 2], 3);

		// 生成随机样例
		for (let x = 1; x <= 50; x++) {
			let sample = [];
			let out = [];
			let ans = [];
			let count = Math.floor((Math.random() + 1) * x);
			for (let a = 0; a < count; a++) {
				sample.push([
					Math.floor(Math.random() * 0x7fffffff),
					Math.floor(Math.random() * 0x7fffffff),
					Math.floor(Math.random() * 0x7fffffff)
				]);
			}
			for (let a = 0; a < count; a++) {
				instance.exports.PQadd(0, a,
					sample[a][0],
					sample[a][1],
					sample[a][2]
				);
			}
			for (let a = 0; a < count; a++) {
				let pos = instance.exports.PQpick(0, count - a);
				out.push([
					memory[pos / 4 + 0],
					memory[pos / 4 + 1],
					memory[pos / 4 + 2]
				]);
			}
			ans = sample.sort((a, b) => a[2] - b[2]);
			// console.log(String(sample));
			// 在第三个数有重复的时候有可能结果正确但是样例不会过，我目前还没做特判
			test("样例" + x, String(out), String(ans));
		}
	}

	// 寻路测试
	if (true) {
		instance = await WebAssembly.instantiate(wmodule, wimport);
		memory = new Uint32Array(instance.exports.memory.buffer);
		/*test("1", instance.exports.growSize(4), 1);
		//console.log(require("util").inspect(instance.exports,true,null,true));
		instance.exports.init(2, 2);
		memory[0] = 0;
		memory[1] = 0;
		memory[2] = 0;
		memory[3] = 0;
		test(2, instance.exports.a_star(0, 0, 1, 1), 2);
		pathWrite();
		instance.exports.init(3, 1);
		memory[0] = 0;
		memory[1] = 0;
		memory[2] = 0;
		test(3, instance.exports.a_star(0, 0, 2, 0), 3);
		pathWrite();
		instance.exports.init(3, 3);
		memory[0] = 0;
		memory[1] = 0;
		memory[2] = 0;
		memory[3] = 1;
		memory[4] = 1;
		memory[5] = 0;
		memory[6] = 0;
		memory[7] = 0;
		memory[8] = 0;
		test(4, instance.exports.a_star(0, 0, 0, 2), 5);
		pathWrite();*/
		let time1 = 0;
		let time2 = 0;

		for (let x = 1; x <= 1000; x++) {
			let mapX = Math.floor(Math.random() * 1000 + 4);
			let mapY = Math.floor(Math.random() * 1000 + 4);
			let c = instance.exports.init(mapX, mapY);
			if (c === 0) {
				console.log("无法初始化");
				continue;
			}
			memory = new Uint32Array(instance.exports.memory.buffer);
			let x1, y1, x2, y2, mi = Math.random();
			for (let i = 0; i < mapX * mapY; i++) {
				memory[i] = Math.random() < mi ? 0 : 1;
			}
			//wimport.debug.inspect();
			do {
				x1 = Math.floor(Math.random() * mapX);
				y1 = Math.floor(Math.random() * mapY);
			} while (memory[y1 * mapX + x1] === 1);
			do {
				x2 = Math.floor(Math.random() * mapX);
				y2 = Math.floor(Math.random() * mapY);
			} while (memory[y2 * mapX + x2] === 1);
			//console.log("rd")
			let t1 = Number(new Date());
			let out = instance.exports.a_star(x1, y1, x2, y2);
			//console.log("su")
			let t2 = Number(new Date());
			let ans = pathAns(mapX, mapY, x1, y1, x2, y2, memory)
			//console.log("pr")
			//console.log(mapX, mapY, x1, y1, x2, y2)
			let t3 = Number(new Date());
			time1 += t2 - t1;
			time2 += t3 - t2;

			test("t" + x, out, ans);
			if (out !== ans) {
				let path = [];
				let st = instance.exports.pathStart.value / 4;
				for (let i = 0; i < out; i++) {
					let dt = memory[st + i];
					path.push(dt >> 16);
					path.push(dt & 0xffff);
				}
				wimport.debug.inspect(x1, y1, x2, y2, path);
			}
		}

		console.log("wasm", time1, "ans", time2, "wasm/ans", time1 / time2);
	}

	// fs.writeFileSync("main.wat",module.toText({foldExprs: true, inlineExport: true}));
	// module.destroy();
})();

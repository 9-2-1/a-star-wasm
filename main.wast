;; 最前面粗略讲一下 wast格式
;; 我参考了 MDN的教程 https://developer.mozilla.org/zh-CN/docs/WebAssembly/Understanding_the_text_format

;; 大体都是 (name arg1 arg2 ...) 的格式，其中argx可以是新的括号
;; ;;打头，(; ;)之间是注释

;; name    解释
;; ----    ----
;; module  整个项目 (固定的，在最外面)
;; global  全局变量 (global $标记名 类型)
;; memory  存储空间 (memory 最小空间页数 最大空间页数(可忽略)) 一页64KB
;; func    过程 (func $标记名 ...)
;; param   参数 (param $标记名 类型) 在func里用
;; local   本地变量 (local $标记名 类型) 在func里用
;; result  设定返回值类型 (result 类型) 在func里用
;; export  导出标记
;;           可以在 module 里面单独
;;             (export (内容name $标记名) "导出名字")
;;           也可以在内容里面
;;             (export "导出名字")
;; table, data, elem, import没讲，因为我目前没有用它们

;; func内代码简介
;; 代码可以写成后缀表达式，也可以带括号写成前缀表达式，我比较喜欢带括号
;; 一般情况下带括号的操作格式是：
;;   (name arg1 arg2 ...)
;;   argx 可能是 $标记名 或者 (代码) ($标记名也可以用对应的数字代替)

;; 类型列表
;; 名字      说明       大小
;; ----      ----       ----
;; i32       32位整数   4字节
;; i64       64位整数   4字节
;; f32       32位浮点数 8字节
;; f64       64位浮点数 8字节
;; v128      数据组合   16字节
;; externref 引用标记   不知道

;; func内常用操作(这里用 $x 代表 $标记名，(x)代表需要插入代码)

;; local.set $a (b) 把本地变量或参数a设为b
;; local.tee $a (b) 把本地变量或参数a设为b并返回b
;; local.get $a 读取本地变量或参数a
;; global.set $a (b) 把全局变量a设为b
;; global.get $a 读取全局变量a

;; 类型.load offset=a (b) 从memory上的b+a位置(从0开始，单位是字节，注意！)读取类型数据
;; 类型.store offset=a (b) (c) 在memory上的b+a位置保存数据c

;; (select 类型 (a) (b) (c)) 如果a返回b否则返回c,三目运算符
;;   类型在特定情况下不能忽略
;; (if (a) (then b...)) 如果那么
;; (if (a) (then b...) (else c...)) 如果那么否则
;; (loop $a b...) 设定向括号开始处跳转的标记a
;; (block $a b...) 设定向括号结尾处跳转的标记a
;;   其实loop和block也能指定返回值类型，这里不讲
;; (br $a) 跳转到标记a
;; (br_if $a (b)) 如果b跳转到标记a
;; (return) 返回(无返回值)
;; (return (a)) 返回a

;; (drop (a)) 忽略a的返回值(在wast中，有返回值的操作的返回值必须被处理，否则必须用drop忽略)

;; 更多指令请查看 https://webassembly.github.io/spec/core/_download/WebAssembly.pdf
;; 指路: 66页4.3.2开始是数学运算列表(使用的时候要把前面的i或者f换成完整的类型名,例如 iadd 变成 i32.add 或者 i64.add
;;       87页4.4开始是可用指令列表
;;       全是英文和各种概念，阅读前要有心理准备

;; 看不懂的话下面全是实例，读一遍应该就大概了解了

(module
	(memory (;min;) 0 (;max;) 104857600(;=100MB;))
	(func $a (export "a")
				(param $x i64)
				(result i64)
				(local.get $x)
				)
	)

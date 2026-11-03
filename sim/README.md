# 仿真源码与脚本

本目录保留原有 testbench、ModelSim .do 脚本、PowerShell 辅助脚本和字库生成工具。
编译库、波形、日志及历史结果已清理，运行脚本后会重新生成。

在 ModelSim 中进入本目录，按需要运行：
- do run_basic.do：基础算法及相关模块自检。
- do run_full_hd.do：全高清相关测试。
- do run_ui_migration.do：中文 UI、菜单与包装器测试。
- do run_inspection_user_control.do：单帧录入控制测试。
- do run_snapshot_footer.do：截图与底栏相关测试。
- 其他 run_*.do：对应功能专项测试。

各脚本以实际 TEST PASSED / TEST FAILED 和错误数为准；这些入口不代表一次运行覆盖整机全部功能。
脚本依赖 Efinity 仿真库时，需匹配本机工具安装路径。
ddr_port_declaration_only.v 仅为端口声明夹具，不提供厂商 DDR 行为仿真。
字库资产已经存在；generate_ui_font.ps1 仅在修改 UI 字符时使用，依赖 Microsoft YaHei 字体。


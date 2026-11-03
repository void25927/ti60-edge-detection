onerror {quit -code 1 -f}
if {[file isdirectory src/ui]} {cd sim}
# 中文菜单、逐像素UI和包装器同步三项；结束时自动退出。
# 帧率与截图分别用独立进程执行run_fps.do及run_snapshot_footer.do。
do run_modern_ui.do

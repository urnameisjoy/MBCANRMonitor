#!/usr/bin/python
import sys;
import os;
import os.path;

global Leak_log;
global result_fo;
global dsym_path;
global app_load_addr;
global max_length;
global app_name;

def get_lib_name(str):
	list = str.split(" ");
	return list[1];

def seek_str(begin,str,end):
	result = Leak_log.find(str,begin,end);
	return result;

def translate_stack(list):
    if len(list) == 0:
        return "";
    global app_load_addr;
    print "app_load_addr:%s list:%s" %(app_load_addr, list);
    command = "atos -o %s -l %s" %(dsym_path, app_load_addr);
    for i in range(len(list)):
        addr = list[i];
        command = command + " %s" %(addr);
    print "%s" % (command);
    result = os.popen(command).read();
    if result:
        print "atos success!"
        return result;
    else :
        print "atos failed"
        return result;

def get_addr(str):
	global app_load_addr;
	list = str.split(" ");
	if list[1] != app_name:
		return 0;
	else:
		app_load_addr = list[2];
		addr = list[3];
		return addr;

def translate(begin,key,prefix):
    print "begin translate %s..." %(key);
    singleLogBegin = seek_str(0,"ANR moment",len(Leak_log));
    while singleLogBegin != -1:
        interval_info_list = [];
        func_cnt_list = [];     
        func_type_list = [];    
        system_func_list = [];      
        QQ_func_list = [];      
        QQ_addr_list = [];
        stack_cnt = 0;
        print "singleLogBegin %d..." %(singleLogBegin);
        pre_begin = seek_str(singleLogBegin, prefix, len(Leak_log));
        begin = seek_str(pre_begin, key, len(Leak_log));
        realEnd = seek_str(begin,"\"}", len(Leak_log));
        result_fo.write(Leak_log[singleLogBegin: begin]);
        lastEnd = -1;
        while begin != -1 and pre_begin != -1:
            end = seek_str(begin + 1, "]", realEnd);
            print "pre_begin:%d begin:%d end:%d realEnd:%d\n" %(pre_begin, begin, end, realEnd);
            if end == -1:
                end = realEnd;
            strBegin = begin;
            func_cnt = 0;
            while strBegin != -1:
                strEnd = seek_str(strBegin + 1,",",end);
                if strEnd == -1:
                    strEnd = end;
                str = Leak_log[strBegin + 1 : strEnd];
                print "strBegin:%d strEnd:%d, str:%s\n" %(strBegin, strEnd, str);
                addr = get_addr(str);
                print "get_addr %s, addr: %s..." %(str, addr);
                if addr == 0:		
                    func_type_list.append(0);
                    system_func_list.append(str);
                else:
                    func_type_list.append(1);
                    QQ_addr_list.append(addr);
                func_cnt = func_cnt + 1;
                if strEnd == end:
                    strBegin = -1;
                else:
                    strBegin = strEnd;
            func_cnt_list.append(func_cnt);
            if lastEnd != -1:
                info = Leak_log[lastEnd + 1: begin];
            else:
                info = Leak_log[pre_begin: begin];
            print "info:%s\n" %(info);
            interval_info_list.append(info);
            lastEnd = end;
            stack_cnt = stack_cnt + 1;
            pre_begin = seek_str(end, prefix, realEnd);
            begin = seek_str(end, key, realEnd);
            if begin == -1:
                break;
        if stack_cnt > 0:
            QQ_stack = "";
            print "QQ_addr_list:%s\n func_cnt_list:%s\n system_func_list:%s\n interval_info_list:%s\n" %(QQ_addr_list, func_cnt_list, system_func_list, interval_info_list);
            if len(QQ_addr_list) > max_length:
                remain = len(QQ_addr_list)%max_length;
                if remain == 0:
                    split_num = len(QQ_addr_list)/max_length;
                else:
                    split_num = len(QQ_addr_list)/max_length + 1;
                current = 0;
                while (current < split_num):
                    end = 0;
                    if (current*(max_length+1) > len(QQ_addr_list)):
                        end = len(QQ_addr_list) -1;
                    else:
                        end = (current + 1)*(max_length) - 1;
                        print "translate %s_addr_list begin:%d end:%d" %(app_name,current*max_length,end);
                    split_stack = translate_stack(QQ_addr_list[current*max_length:end]);
                    current = current + 1;
                    QQ_stack = QQ_stack + split_stack;
            else:
                QQ_stack = translate_stack(QQ_addr_list);
            # if QQ_stack:
                QQ_func_list = QQ_stack.split("\n");
                sys_index = 0;
                QQ_index = 0;
                type_index = 0;
                i = 0;
                print "stack_cnt:%d" %(stack_cnt);
                while i < stack_cnt:
                    func_cnt = func_cnt_list[i];
                    print "%s%d num:%d (\n"%(key, i, func_cnt);
                    result_fo.write( "%s (\n"%(interval_info_list[i]));
                    j = 0;
                    while j < func_cnt:
                        if func_type_list[type_index] == 0:
                            print "\t\"%s\"\n" % (system_func_list[sys_index]);
                            if sys_index < len(system_func_list):
                                result_fo.write( "\t\"%s\"\n" % (system_func_list[sys_index]) );
                                sys_index = sys_index + 1;
                        else :

                            print "\t\"%d QQ %s\"\n" % (j+1 , QQ_func_list[QQ_index]);
                            if QQ_index < len(QQ_func_list):
                                result_fo.write( "\t\"%d %s %s\"\n" % (j , app_name,QQ_func_list[QQ_index]) );
                                QQ_index = QQ_index + 1;
                        j = j + 1;
                        type_index = type_index + 1;
                    i = i + 1;
                    # print ")\n"
                    result_fo.write( ")\n");
    	print "end translate %s..." %(key);
        singleLogBegin = seek_str(realEnd,"ANR moment",len(Leak_log));
        result_fo.write(Leak_log[realEnd: singleLogBegin]);
        result_fo.write( "\n");

print"Begin Translation......";
dsym_path = sys.argv[1];
leak_path = sys.argv[2];
dsym_path = dsym_path + "/Contents/Resources/DWARF";
files = os.listdir(dsym_path);
file_name = os.path.basename(leak_path);
app_name = files[0];
dsym_path = os.path.join(dsym_path,app_name);
#app_name = os.path.split("/");
print "APP Name:%s" %(app_name);
leak_fo = open(leak_path,"r");
max_length = 10000;
translated_file = file_name + "_translated.log";
result_fo = open(translated_file,"w");
Leak_log = leak_fo.read();
translate(0, "[0", "Stack of thread");
print"end Translation......";

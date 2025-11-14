#!/usr/bin/python3

import sys
import json
import re


edges = {}
nodes = {}
counter = 1


def edges_nodes(parent, theobject):

    global edges, nodes, counter


    #curparent = str(parent)
    flag = False
    idx = counter
    counter += 1    
    curparent = parent    
    #print(curparent + " -> ", end='')
    #if dict then store key as parent
    if (isinstance(theobject,dict)):
        #print ("In the dict")


        for k,v in theobject.items():
            #flag = True  # Not empty
            
            if (isinstance(v, dict)):
                curparent = k
                if idx not in nodes.keys():
                    nodes[idx] = []
                nodes[idx].append("<"+ str(k) + "> "+str(k)+ ": ")
                
                retidx = edges_nodes(curparent, v)
                if retidx not in edges.keys():
                    edges[retidx] = []
                edges[retidx].append(str(idx)+":"+ str(curparent))  # will print idx:key -> retidx
            elif (isinstance(v, list)):
                curparent = k
                if idx not in nodes.keys():
                    nodes[idx] = []
                nodes[idx].append("<"+ str(k) + "> "+str(k)+ ": ")
                for i in v:
                    
                    retidx = edges_nodes(curparent, i)

                    if retidx not in edges.keys():
                        edges[retidx] = []
                    edges[retidx].append(str(idx)+":"+ str(curparent))
            else :
                if idx not in nodes.keys():
                    nodes[idx] = []
                nodes[idx].append(str(k) + ":" + str(v))


    return idx

# End of def edge_nodes(parent, theobject)

print('digraph tree {')

print('graph [rankdir = "LR", nodesep=0.0, ranksep=1.0];')
print('node [fontsize = "9", shape = "Mrecord", height=0.1, color=darkgreen];')
print('edge [color=brown, arrowhead=vee];')
with open(sys.argv[1], 'r') as my_file:
    data = json.load(my_file)
    retidx = edges_nodes("AWS Global", data)



# Dump edge list in Graphviz DOT format


for i,j in nodes.items():
    # j is a list
    s = "|".join(j)
    print(str(i)+'[label="' + str(s) + '"];')

#curi = previ = 0
#print(edges)
for i,j in edges.items():
#    print('-------------key and value ' + str(i) + ' ' + str(j))
    for ele in j:
        strele = str(ele)
        if (re.search('^\d+$',strele)) :
            if strele not in nodes.keys():
#                print('----------------- Not in ' + str(ele))
                print(edges[int(strele)][0] + "->" + str(i) + ";")
                
        elif(i in nodes.keys()):         
            print(strele + "->" + str(i) + ";")
            
    
    
print('}')



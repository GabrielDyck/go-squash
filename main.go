package main

import (
	"fmt"
	"os"
)

func main() {
	workingDir:=os.Args[1]
	baseBranch:=os.Args[2]
	commitMessage:=os.Args[3]
	checkPrecondition(workingDir,"working directory is nil")
	checkPrecondition(baseBranch, "base branch is nil")

	fmt.Printf("Working directory: %s \n", workingDir)
	fmt.Printf("Base branch: %s \n", baseBranch)
	fmt.Printf("Commit msg: %s \n", commitMessage)
}



func checkPrecondition(value string, errorMsg string){
	if &value ==nil{
		panic("Cannot continue: %s", errorMsg)
	}
}
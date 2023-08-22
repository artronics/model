function Editor() {
    return (
        <div className="flex flex-row h-full items-stretch">
            <ol className="w-16 mr-1 text-center border-r-[1px] border-black">
                <li>1</li>
                <li>&nbsp;</li>
                <li>2</li>
                <li>3345</li>
                <li>3</li>
            </ol>
            <ol>
                <li>line 1</li>
                <li>virtual line</li>
                <li>line <span>2</span></li>
                <li>line 3 <span>virtual text</span></li>
            </ol>
        </div>
    )
}

export default Editor
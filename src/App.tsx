import {useEffect} from 'react'
import './App.css'
import {invoke} from '@tauri-apps/api';

function App() {
    useEffect(() => {
        invoke('greet', {name: 'World'})
            // `invoke` returns a Promise
            .then((response) => console.log(response))
    }, []);

    return (
        <h1 className="text-3xl m-10 font-bold underline">
            Hello worlds <i className="fa fa-camera"></i>
        </h1>

    )
}

export default App

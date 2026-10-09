object FrmOfertasMarketplace: TFrmOfertasMarketplace
  Left = 0
  Top = 0
  Caption = 'Ofertas - Marketplace'
  ClientHeight = 520
  ClientWidth = 900
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  TextHeight = 15
  object pnlTopo: TPanel
    Left = 0
    Top = 0
    Width = 900
    Height = 60
    Align = alTop
    Color = clWhite
    ParentBackground = False
    TabOrder = 0
    object lblTitulo: TLabel
      Left = 16
      Top = 18
      Width = 55
      Height = 21
      Caption = 'Ofertas'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -16
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
  end
  object pnlFiltros: TPanel
    Left = 0
    Top = 60
    Width = 900
    Height = 60
    Align = alTop
    TabOrder = 4
    object lblDataDe: TLabel
      Left = 16
      Top = 10
      Width = 55
      Height = 15
      Caption = 'Atualiz. de'
    end
    object lblDataAte: TLabel
      Left = 136
      Top = 10
      Width = 58
      Height = 15
      Caption = 'Atualiz. at'#233
    end
    object lblStatus: TLabel
      Left = 256
      Top = 10
      Width = 32
      Height = 15
      Caption = 'Status'
    end
    object lblFiltroNome: TLabel
      Left = 446
      Top = 10
      Width = 96
      Height = 15
      Caption = 'Nome do Produto'
    end
    object lblFiltroItemID: TLabel
      Left = 646
      Top = 10
      Width = 38
      Height = 15
      Caption = 'Item ID'
    end
    object dtpDataDe: TDateTimePicker
      Left = 16
      Top = 28
      Width = 110
      Height = 23
      Date = 44197.000000000000000000
      Time = 44197.000000000000000000
      TabOrder = 0
    end
    object dtpDataAte: TDateTimePicker
      Left = 136
      Top = 28
      Width = 110
      Height = 23
      Date = 44197.000000000000000000
      Time = 44197.000000000000000000
      TabOrder = 1
    end
    object cbxStatus: TComboBox
      Left = 256
      Top = 28
      Width = 180
      Height = 23
      Style = csDropDownList
      TabOrder = 2
    end
    object edtFiltroNome: TEdit
      Left = 446
      Top = 28
      Width = 190
      Height = 23
      TabOrder = 3
    end
    object edtFiltroItemID: TEdit
      Left = 646
      Top = 28
      Width = 100
      Height = 23
      TabOrder = 4
    end
    object CmdConsultar: TBitBtn
      Left = 756
      Top = 27
      Width = 120
      Height = 25
      Caption = 'Consultar'
      TabOrder = 5
      OnClick = CmdConsultarClick
    end
  end
  object Grid: TStringGrid
    Left = 0
    Top = 120
    Width = 900
    Height = 200
    Align = alTop
    ColCount = 9
    DefaultColWidth = 110
    FixedCols = 0
    RowCount = 1
    FixedRows = 0
    Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goRowSelect]
    TabOrder = 1
    ColWidths = (
      90
      210
      100
      90
      70
      70
      80
      90
      90)
  end
  object pnlAcoes: TPanel
    Left = 0
    Top = 320
    Width = 900
    Height = 56
    Align = alTop
    TabOrder = 2
    object CmdAtualizarTodos: TBitBtn
      Left = 16
      Top = 12
      Width = 160
      Height = 32
      Caption = 'Atualizar Todos'
      TabOrder = 0
      OnClick = CmdAtualizarTodosClick
    end
    object CmdAtualizarSelecionado: TBitBtn
      Left = 184
      Top = 12
      Width = 180
      Height = 32
      Caption = 'Atualizar Selecionado'
      TabOrder = 1
      OnClick = CmdAtualizarSelecionadoClick
    end
    object CmdVincularProduto: TBitBtn
      Left = 372
      Top = 12
      Width = 160
      Height = 32
      Caption = 'Vincular Produto'
      TabOrder = 2
      OnClick = CmdVincularProdutoClick
    end
    object CmdIncluirProduto: TBitBtn
      Left = 540
      Top = 12
      Width = 160
      Height = 32
      Caption = 'Incluir Produto'
      TabOrder = 3
      OnClick = CmdIncluirProdutoClick
    end
  end
  object MemoLog: TMemo
    Left = 0
    Top = 376
    Width = 900
    Height = 144
    Align = alClient
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Consolas'
    Font.Style = []
    ParentFont = False
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 3
  end
end
